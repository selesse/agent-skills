#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches all PR comments + review threads via a single GraphQL call.
# Filters bot noise, threads inline comments with diff context.
# Resolved threads are collapsed by default; pass --include-resolved to expand.
#
# Usage: ruby fetch_review.rb <pr-url-or-number> [owner/repo] [--include-resolved]
#
# Examples:
#   ruby fetch_review.rb 491550
#   ruby fetch_review.rb https://github.com/shop/world/pull/491550
#   ruby fetch_review.rb 123 Shopify/some-repo
#   ruby fetch_review.rb 491550 --include-resolved

require "json"
require "open3"

ALLOWED_BOTS = %w[
  binks-code-reviewer
].freeze

GRAPHITE_STACK_MARKER = "This stack of pull requests is managed by"
BINKS_STATUS_MARKER = "<!-- binks-review-status -->"

def parse_args
  args = ARGV.dup
  include_resolved = !!args.delete("--include-resolved")

  input = args[0] || abort("Usage: ruby fetch_review.rb <pr-url-or-number> [owner/repo] [--include-resolved]")

  pr_number = input[/(\d+)/, 1] || abort("Could not extract PR number from: #{input}")

  repo = if args[1]
    owner, name = args[1].split("/")
    { owner: owner, name: name }
  elsif input.match?(%r{github\.com/})
    match = input.match(%r{github\.com/([^/]+)/([^/]+)/pull/})
    match ? { owner: match[1], name: match[2] } : { owner: "shop", name: "world" }
  elsif input.match?(%r{graphite\.(com|dev)/})
    match = input.match(%r{graphite\.(?:com|dev)/github/pr/([^/]+)/([^/]+)/(\d+)})
    match ? { owner: match[1], name: match[2] } : { owner: "shop", name: "world" }
  else
    { owner: "shop", name: "world" }
  end

  [pr_number.to_i, repo, include_resolved]
end

QUERY = File.read(File.join(__dir__, "pr_comments.graphql"))

INT_VARS = %w[number].freeze

def gh_graphql(variables)
  cmd = ["gh", "api", "graphql", "-f", "query=#{QUERY}"]
  variables.each do |k, v|
    flag = INT_VARS.include?(k.to_s) ? "-F" : "-f"
    cmd.push(flag, "#{k}=#{v}")
  end

  stdout, stderr, status = Open3.capture3(*cmd)
  abort("gh api failed: #{stderr}") unless status.success?
  JSON.parse(stdout, symbolize_names: true)
end

def fetch_all(pr_number, repo)
  all_comments = []
  all_reviews = []
  all_threads = []
  pr_data = nil

  comments_cursor = nil
  reviews_cursor = nil
  threads_cursor = nil

  loop do
    vars = { owner: repo[:owner], name: repo[:name], number: pr_number.to_s }
    vars[:commentsCursor] = comments_cursor if comments_cursor
    vars[:reviewsCursor] = reviews_cursor if reviews_cursor
    vars[:threadsCursor] = threads_cursor if threads_cursor

    result = gh_graphql(vars)
    pr = result.dig(:data, :repository, :pullRequest)
    abort("PR not found: #{pr_number}") unless pr

    pr_data ||= pr

    all_comments.concat(pr[:comments][:nodes])
    all_reviews.concat(pr[:reviews][:nodes])
    all_threads.concat(pr[:reviewThreads][:nodes])

    comments_has_more = pr[:comments][:pageInfo][:hasNextPage]
    reviews_has_more = pr[:reviews][:pageInfo][:hasNextPage]
    threads_has_more = pr[:reviewThreads][:pageInfo][:hasNextPage]

    comments_cursor = pr[:comments][:pageInfo][:endCursor] if comments_has_more
    reviews_cursor = pr[:reviews][:pageInfo][:endCursor] if reviews_has_more
    threads_cursor = pr[:reviewThreads][:pageInfo][:endCursor] if threads_has_more

    break unless comments_has_more || reviews_has_more || threads_has_more
  end

  [pr_data, all_comments, all_reviews, all_threads]
end

def bot?(author)
  return true unless author
  author[:__typename] == "Bot"
end

def allowed_author?(author)
  return false unless author
  return true unless bot?(author)

  ALLOWED_BOTS.include?(author[:login])
end

def hidden_general_comment?(body)
  return false unless body
  body.include?(GRAPHITE_STACK_MARKER) || body.include?(BINKS_STATUS_MARKER)
end

INDENT = "    "

def indent(text)
  text.gsub(/^/, INDENT)
end

def format_diff_context(diff_hunk)
  return nil unless diff_hunk
  lines = diff_hunk.lines.last(10).map(&:rstrip)
  lines.join("\n")
end

def author_label(author)
  login = author&.dig(:login) || "unknown"
  bot?(author) ? "#{login} [BOT]" : login
end

def thread_location(thread)
  c = thread[:comments][:nodes].first
  return "(unknown location)" unless c
  loc = c[:path].dup
  loc << ":#{c[:startLine]}-#{c[:line]}" if c[:startLine] && c[:line]
  loc << ":#{c[:line]}" if !c[:startLine] && c[:line]
  loc
end

def render_thread(thread, out)
  comments = thread[:comments][:nodes].select { |c| allowed_author?(c[:author]) }
  return if comments.empty?

  top, *replies = comments
  out << "---"
  markers = []
  markers << "[OUTDATED]" if thread[:isOutdated]
  markers << "[RESOLVED by @#{thread.dig(:resolvedBy, :login) || "unknown"}]" if thread[:isResolved]
  prefix = markers.empty? ? "" : "#{markers.join(" ")} "
  out << "### #{prefix}`#{thread_location(thread)}`"
  out << "Comment ID: `#{top[:databaseId]}` — #{top[:url]}" if top[:databaseId]

  diff = format_diff_context(top[:diffHunk])
  if diff
    out << "```diff"
    out << diff
    out << "```"
  end

  out << "**#{author_label(top[:author])}** (#{top[:createdAt]}):"
  out << indent(top[:body].strip)

  replies.sort_by { |r| r[:createdAt] }.each do |reply|
    out << ""
    out << "  > **#{author_label(reply[:author])}** (#{reply[:createdAt]}):"
    out << indent("> #{reply[:body].strip.gsub("\n", "\n> ")}")
  end

  out << ""
end

def format_output(pr_data, comments, reviews, threads, include_resolved:)
  out = []

  out << "# PR ##{pr_data[:url][/\d+$/]}: #{pr_data[:title]}"
  out << "Author: #{pr_data.dig(:author, :login)} | State: #{pr_data[:state]}"
  out << ""

  if pr_data[:body] && !pr_data[:body].strip.empty?
    out << "## Description"
    out << pr_data[:body].strip
    out << ""
  end

  visible_comments = comments.select { |c| allowed_author?(c[:author]) && !hidden_general_comment?(c[:body]) }
  if visible_comments.any?
    out << "## General Comments"
    visible_comments.each do |c|
      out << "**#{author_label(c[:author])}** (#{c[:createdAt]}):"
      out << indent(c[:body].strip)
      out << ""
    end
  end

  review_bodies = reviews
    .select { |r| allowed_author?(r[:author]) && r[:body] && !r[:body].strip.empty? }

  if review_bodies.any?
    out << "## Review Summaries"
    review_bodies.each do |r|
      out << "**#{author_label(r[:author])}** [#{r[:state]}] (#{r[:createdAt]}):"
      out << indent(r[:body].strip)
      out << ""
    end
  end

  visible_threads = threads.select do |t|
    t[:comments][:nodes].any? { |c| allowed_author?(c[:author]) }
  end

  unresolved = visible_threads.reject { |t| t[:isResolved] }
  resolved = visible_threads.select { |t| t[:isResolved] }

  if unresolved.any? || resolved.any?
    out << "## Inline Review Comments"

    if resolved.any? && !include_resolved
      out << "✅ #{resolved.size} resolved thread#{resolved.size == 1 ? "" : "s"} hidden (pass --include-resolved to show):"
      resolved.each do |t|
        top = t[:comments][:nodes].first
        resolver = t.dig(:resolvedBy, :login) || "unknown"
        out << "  - `#{thread_location(t)}` — #{author_label(top[:author])} (resolved by @#{resolver})"
      end
      out << ""
    elsif resolved.any?
      out << "(showing #{resolved.size} resolved thread#{resolved.size == 1 ? "" : "s"} because --include-resolved was passed)"
      out << ""
    end

    threads_to_render = include_resolved ? unresolved + resolved : unresolved
    threads_to_render.each { |t| render_thread(t, out) }
  end

  out.join("\n")
end

pr_number, repo, include_resolved = parse_args
pr_data, comments, reviews, threads = fetch_all(pr_number, repo)
puts format_output(pr_data, comments, reviews, threads, include_resolved: include_resolved)
