#! /usr/bin/env ruby
#
#  check-kannel
#
# DESCRIPTION:
#   This plugin checks if Kannel SMSC connections are online.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   check-kannel -h host -p port -P password
#
# NOTES:
#
# LICENSE:
#   Pedro Chambino    <https://github.com/pchambino>
#   Tiago Varela    <https://github.com/tiagovarela>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'net/http'
require 'rexml/document'

#
# Check Kannel
#
class CheckKannel < Sensu::Plugin::Check::CLI
  option :host,
         short: '-h HOST',
         long: '--host HOST',
         description: 'Your Kannel endpoint',
         default: 'localhost'

  option :port,
         short: '-P PORT',
         long: '--port PORT',
         description: 'Your Kannel port',
         default: 13000, # rubocop:disable NumericLiterals
         proc: proc(&:to_i)

  option :password,
         short: '-p PASSWORD',
         long: '--password PASSWORD',
         description: 'Your Kannel password'

  option :pattern,
         short: '-i PATTERN',
         long: '--id PATTERN',
         description: 'Match a SMSC id against this pattern'

  def run
    path = "/status.xml?password=#{config[:password]}"

    begin
      response = Net::HTTP.get(config[:host], path, config[:port])
    rescue => e
      critical e
    end

    document = REXML::Document.new(response)
    critical 'Invalid XML document' if document.root.nil?
    critical 'Invalid root element' if 'gateway' != document.root.name
    critical 'Denied' if 'Denied' == document.root.text.strip

    smscs_status = Hash[REXML::XPath.each(document, '//smsc').map do |smsc|
      [smsc.text('id'), smsc.text('status')]
    end]

    smscs_status.reject! { |id, _| /#{config[:pattern]}/ !~ id } if config[:pattern]

    offline_smscs = smscs_status.reject { |_, status| status.start_with? 'online' }.keys

    if offline_smscs.any?
      critical "Offline: #{offline_smscs.join(', ')}"
    else
      ok "Online: #{smscs_status.count}"
    end
  end
end
