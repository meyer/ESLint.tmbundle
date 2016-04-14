require 'shellwords'
require 'open3'
require 'json'

# Exit codes from ~/Library/Application Support/TextMate/Managed/Bundles/Bundle Support.tmbundle/Support/shared/lib/bash_init.sh
# 200: discard
# 201: replace text
# 202: replace document
# 203: insert text
# 204: insert snippet
# 205: show html
# 206: show tooltip
# 207: create new document

# yoinked from scm-diff-bundle: https://git.io/vzVux
def reset_marks(lines, mark)
  args = [ "--clear-mark=#{mark}" ]
  unless lines.empty?
    args << "--set-mark=#{mark}"
    lines.each { |n| args << "--line=#{n}" }
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
  "Here they are (drumroll please\u2026)"
].sample

def validate
  eslint = ENV['TM_ESLINT'] || 'eslint'

  # Change to file directory so ESLint looks for the local .eslintrc
  Dir.chdir File.dirname(ENV['TM_FILEPATH'])

  args = [
    '-f',
    'json',
    '--no-color',
    '--stdin',
    '--stdin-filename',
    File.basename(ENV['TM_FILEPATH']),
  ]

  ENV['PATH'] = ENV['PATH'].split(':').unshift('/usr/local/bin', '/usr/bin', '/bin').uniq.join(':')

  if `which #{eslint}`.chomp === ''
    puts '`eslint` could not be found on your PATH'
    exit 206
  end

  # Run eslint, get output
  Open3.popen3(eslint, *args) do |i,o,e,t|
    i.puts ARGF.read
    i.close_write

    exit_status = Integer(t.value.exitstatus)
    results = begin JSON.parse(o.read) rescue nil end

    unless results
      puts "Error running eslint"
      puts "#{e.read}"
      exit 206
    end

    result = results.first

    if result['messages'].length === 0
      puts NO_LINT
      reset_marks([], 'error')
      reset_marks([], 'warning')
      exit 206
    end

    error_lines = []
    warning_lines = []
    msg_count = result['messages'].length
    s = msg_count == 1 ? '' : 's'

    puts "#{msg_count} lint message#{s}! #{YES_LINT}"

    result['messages'].each do |msg|
      if msg['line'] && msg['column']
        print "Line #{msg['line']}, column #{msg['column']}: "
      end

      if msg['severity'] === 2
        print 'Error! '
        error_lines << "#{msg['line']}:#{msg['column']}"
      else
        print 'Warning! '
        warning_lines << "#{msg['line']}:#{msg['column']}"
      end

      puts msg['message']
    end

    reset_marks(error_lines, 'error')
    reset_marks(warning_lines, 'warning')

    exit 206

  end
end

# validate if __FILE__ == $PROGRAM_NAME
