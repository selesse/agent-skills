#!/usr/bin/env ruby
# frozen_string_literal: true

# Respond to a single PR review thread: post a reply, add a reaction, and resolve the thread.
#
# Usage:
#   ruby respond_to_thread.rb <pr-url-or-number> <comment-id-or-url> [options]
#
# Options:
#   --reply BODY        Post a reply to the thread (use - to read from stdin)
#   --reaction +1|-1    Add a thumbs-up or thumbs-down reaction to the original comment
#   --resolve           Mark the thread as resolved
#   --repo OWNER/NAME   Repo to act on (required, unless inferable from a PR/comment URL)
#
# Examples:
#   # Reply, react 👍, and resolve in one shot
#   ruby respond_to_thread.rb 682891 3190948932 \
#     --reply "Fixed in this revision." --reaction +1 --resolve
#
#   # Read a long reply from stdin
#   echo "..." | ruby respond_to_thread.rb 682891 https://github.com/shop/world/pull/682891#discussion_r3190948932 \
#     --reply - --reaction -1 --resolve
#
# Comment ID can be:
#   - Bare numeric databaseId: 3190948932
#   - Comment URL: https://github.com/shop/world/pull/682891#discussion_r3190948932
#
# The script handles the three different identifiers GitHub uses (comment databaseId,
# comment node ID, thread node ID) so callers don't have to.

require "json"
require "open3"
require "optparse"

def parse_args
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = "Respond to a single PR review thread: reply, react, and resolve.\n\n" \
      "Usage: respond_to_thread.rb <pr-url-or-number> <comment-id-or-url> [options]"

    opts.separator ""
    opts.separator "Options:"
    opts.on("--reply BODY", "Reply to post (use - to read from stdin)") { |v| options[:reply] = v }
    opts.on("--reaction REACTION", "Reaction on the original comment: +1 or -1") { |v| options[:reaction] = v }
    opts.on("--resolve", "Mark the thread as resolved") { options[:resolve] = true }
    opts.on("--repo OWNER/NAME", "Repo to act on (required unless a PR/comment URL is passed)") { |v| options[:repo] = v }
    opts.on("-h", "--help", "Show this help") { puts opts; exit }

    opts.separator ""
    opts.separator "Arguments:"
    opts.separator "    <pr-url-or-number>    PR number (e.g. 905126) or PR URL"
    opts.separator "    <comment-id-or-url>   Comment databaseId (e.g. 3190948932) or a #discussion_r<id> URL"

    opts.separator ""
    opts.separator "Examples:"
    opts.separator "    # Reply, react 👍, and resolve in one shot"
    opts.separator "    respond_to_thread.rb 905126 3190948932 --repo shop/world \\"
    opts.separator "      --reply \"Fixed in this revision.\" --reaction +1 --resolve"
    opts.separator ""
    opts.separator "    # Long reply from stdin; repo inferred from the comment URL"
    opts.separator "    cat reply.txt | respond_to_thread.rb 905126 \\"
    opts.separator "      https://github.com/shop/world/pull/905126#discussion_r3190948932 \\"
    opts.separator "      --reply - --reaction +1 --resolve"
  end

  positional = parser.parse(ARGV)
  abort(parser.help) if positional.size < 2

  pr_input, comment_input = positional

  pr_number = case pr_input
  when /\A\d+\z/ then pr_input.to_i
  when %r{/pull/(\d+)} then ::Regexp.last_match(1).to_i
  else abort("Invalid PR: #{pr_input}")
  end

  comment_id = case comment_input
  when /\A\d+\z/ then comment_input.to_i
  when /discussion_r(\d+)/ then ::Regexp.last_match(1).to_i
  else abort("Invalid comment ID: #{comment_input}")
  end

  # No default repo: an agent must be explicit, or pass a full URL we can read it
  # from. Defaulting silently is how comments end up on the wrong repo.
  options[:repo] ||= [pr_input, comment_input]
    .filter_map { |s| s[%r{github\.com/([^/]+/[^/]+)/pull/}, 1] }
    .first
  abort("--repo OWNER/NAME is required (or pass a full PR/comment URL)") unless options[:repo]

  if options[:reply] == "-"
    options[:reply] = $stdin.read
  end

  if options[:reaction] && !["+1", "-1"].include?(options[:reaction])
    abort("--reaction must be +1 or -1")
  end

  unless options[:reply] || options[:reaction] || options[:resolve]
    abort("Nothing to do — pass at least one of --reply / --reaction / --resolve")
  end

  [pr_number, comment_id, options]
end

def gh_api(args, body: nil)
  cmd = ["gh", "api"] + args
  result = nil

  if body
    Open3.popen3(*cmd) do |stdin, stdout, stderr, thread|
      stdin.write(body)
      stdin.close
      out = stdout.read
      err = stderr.read
      status = thread.value
      abort("gh api failed: #{err}") unless status.success?
      result = out
    end
  else
    out, err, status = Open3.capture3(*cmd)
    abort("gh api failed: #{err}") unless status.success?
    result = out
  end

  result
end

def find_thread(repo, pr_number, comment_id)
  owner, name = repo.split("/", 2)
  query = <<~GRAPHQL
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 1) { nodes { databaseId } }
            }
          }
        }
      }
    }
  GRAPHQL

  out = gh_api([
    "graphql",
    "-f", "query=#{query}",
    "-F", "owner=#{owner}",
    "-F", "name=#{name}",
    "-F", "number=#{pr_number}",
  ])

  data = JSON.parse(out, symbolize_names: true)
  threads = data.dig(:data, :repository, :pullRequest, :reviewThreads, :nodes) || []

  match = threads.find do |t|
    t[:comments][:nodes].any? { |c| c[:databaseId] == comment_id }
  end

  abort("No review thread found containing comment #{comment_id} on PR ##{pr_number}") unless match

  match
end

def post_reply(repo, pr_number, comment_id, body)
  out = gh_api([
    "-X", "POST",
    "repos/#{repo}/pulls/#{pr_number}/comments/#{comment_id}/replies",
    "-f", "body=#{body}",
    "--jq", ".id",
  ])
  out.strip
end

def add_reaction(repo, comment_id, reaction)
  out = gh_api([
    "-X", "POST",
    "repos/#{repo}/pulls/comments/#{comment_id}/reactions",
    "-f", "content=#{reaction}",
    "--jq", ".content",
  ])
  out.strip
end

def resolve_thread(thread_node_id)
  query = <<~GRAPHQL
    mutation($id: ID!) {
      resolveReviewThread(input: {threadId: $id}) {
        thread { isResolved }
      }
    }
  GRAPHQL

  out = gh_api([
    "graphql",
    "-f", "query=#{query}",
    "-F", "id=#{thread_node_id}",
    "--jq", ".data.resolveReviewThread.thread.isResolved",
  ])
  out.strip == "true"
end

pr_number, comment_id, options = parse_args

thread = find_thread(options[:repo], pr_number, comment_id)
puts "Thread: #{thread[:id]} (resolved=#{thread[:isResolved]})"

if options[:reply]
  reply_id = post_reply(options[:repo], pr_number, comment_id, options[:reply])
  puts "Reply posted: #{reply_id}"
end

if options[:reaction]
  reaction = add_reaction(options[:repo], comment_id, options[:reaction])
  puts "Reaction added: #{reaction}"
end

if options[:resolve]
  if thread[:isResolved]
    puts "Thread already resolved — skipping"
  else
    resolved = resolve_thread(thread[:id])
    puts "Thread resolved: #{resolved}"
  end
end
