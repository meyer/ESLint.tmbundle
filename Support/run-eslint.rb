#!/usr/bin/env ruby
require 'shellwords'
require 'open3'
require 'json'
require 'timeout'

# Exit codes from ~/Library/Application Support/TextMate/Managed/Bundles/Bundle Support.tmbundle/Support/shared/lib/bash_init.sh
# 200: discard
# 201: replace text
# 202: replace document
# 203: insert text
# 204: insert snippet
# 205: show html
# 206: show tooltip
# 207: create new document

MAX_ERROR_LINES = 20
MAX_LINE_NUM_COUNT = 5

class ESLintError < StandardError; end

# yoinked from scm-diff-bundle: https://git.io/vzVux
def reset_marks(lines, mark)
  return if __FILE__ == $PROGRAM_NAME

  args = ["--clear-mark=#{mark}"]
  unless lines.empty?
    args << "--set-mark=#{mark}"
    lines.each {|n| args << "--line=#{n}"}
  end
  args << ENV['TM_FILEPATH']

  system(ENV['TM_MATE'], *args)
end

NO_LINT = unless [*1..10].sample == 9
  [
    "Lint-free!",
  ]
else
  [
    "You have no lint! Your lint is gone! You have no lint in your document!\nWhere it is, I can\u0027t say, but in your document it\u0027s not!",
    "404: Lint Not Found",
  ]
end.sample

YES_LINT = [
  "I\u0027m impressed.",
  "Here they are (drumroll please\u2026)",
].sample

def validate(filename)
  eslint = ENV['TM_ESLINT'] || 'eslint'

  # Change to file directory so ESLint looks for the local .eslintrc
  Dir.chdir File.dirname(filename)

  args = [
    '-f',
    'json',
    '--no-color',
    '--no-ignore',
    File.basename(filename),
  ]

  ENV['PATH'] = ENV['PATH'].split(':').unshift('/usr/local/bin', '/usr/bin', '/bin').uniq.join(':')

  if `which #{eslint}`.chomp === ''
    puts '`eslint` could not be found on your PATH'
    exit 206
  end

  # Run eslint, get output
  Open3.popen3(eslint, *args) do |i,o,e,t|
    begin
      # Timeout after two seconds
      complete_results = Timeout.timeout(2) do
        jsonOutput = o.read
        results = begin JSON.parse(jsonOutput) rescue nil end

        unless results
          raise ESLintError, "Error running eslint\n#{e.read}"
        end

        if results.length === 0
          raise ESLintError, 'ESLint returned an empty array'
        end

        result = results.first
        if result['messages'].length === 0
          reset_marks([], 'error')
          reset_marks([], 'warning')

          emoji = [
            # "\u{2728}\u{fe0f}", # sparkles
            "\u{1f389}\u{fe0f}", # party popper
            "\u{1f60e}\u{fe0f}", # sunglasses
          ].sample

          raise ESLintError, "#{emoji} #{NO_LINT}"
        end

        # TODO: better way to detect non-JS warnings (file ignored, etc.)
        if result['messages'][0]['fatal'] === false
          raise ESLintError, result['messages'][0]['message']
        end

        error_lines = []
        warning_lines = []
        msg_count = result['errorCount'] + result['warningCount']
        s = msg_count == 1 ? '' : 's'

        title = []
        if result['errorCount'] > 0
          title.push "#{result['errorCount']} error#{result['errorCount'] === 1 ? '' : 's'}"
        end

        if result['warningCount'] > 0
          title.push "#{result['warningCount']} warning#{result['warningCount'] === 1 ? '' : 's'}"
        end

        puts "#{title.join(' and ')}! #{YES_LINT}"

        results_by_message = {}

        result['messages'].each do |msg|
          if msg['severity'] === 2
            msg['emoji'] = "\u{1f6ab}\u{fe0f}"
            error_lines << "#{msg['line']}:#{msg['column']}"
          elsif msg['severity'] === 1
            msg['emoji'] = "\u{26a0}\u{fe0f}"
            warning_lines << "#{msg['line']}:#{msg['column']}"
          end

          results_by_message[msg['message']] ||= []
          results_by_message[msg['message']] << msg
        end

        displayedErrorCount = 0
        results_by_message.each_with_index do |(k,v), idx|
          displayedErrorCount += v.length
          print v[0]['emoji'] + ' '
          if v.length == 1
            print "#{v[0]['line']}:#{v[0]['column']}: "
          elsif v.length > MAX_LINE_NUM_COUNT
            print "#{v[0]['line']}:#{v[0]['column']}, "
            print "#{v[1]['line']}:#{v[1]['column']}, "
            print "and #{v.length - 2} other lines: "
          else
            print v.map {|d| "#{d['line']}:#{d['column']}"}.join(", ")
            puts ":"
            print "    "
          end
          puts k

          if idx > MAX_ERROR_LINES
            notShownCount = result['errorCount'] + result['warningCount'] - displayedErrorCount
            puts "#{notShownCount} more error#{notShownCount > 1 ? 's' : ''} not shown."
            break
          end
        end

        reset_marks(error_lines, 'error')
        reset_marks(warning_lines, 'warning')
      end
    rescue Timeout::Error => e
      puts 'Error: ESLint timed out!'
    rescue ESLintError => e
      puts e.message
    ensure
      begin
        Process.kill('KILL', t.pid)
      rescue Errno::ESRCH
        # pid was already killed
      end
      exit 206
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.length != 1
    abort "Usage: ./run-eslint.rb [path to JS file]"
  end
  validate ARGV[0]
else
  validate ENV['TM_FILEPATH']
end
