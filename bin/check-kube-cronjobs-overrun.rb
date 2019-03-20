#! /usr/bin/env ruby
#
#   check-kube-cronjobs-failed
#
# DESCRIPTION:
# => Check if cronjobs have not run within the scheduled time.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: kube-client
#
# USAGE:
# -s, --api-server URL             URL to API server
# -v, --api-version VERSION        API version. Defaults to 'v1'
#     --in-cluster                 Use service account authentication
#     --ca-file CA-FILE            CA file to verify API server cert
#     --cert CERT-FILE             Client cert to present
#     --key KEY-FILE               Client key for the client cert
# -u, --user USER                  User with access to API
#     --password PASSWORD          If user is passed, also pass a password
#     --token TOKEN                Bearer token for authorization
#     --token-file TOKEN-FILE      File containing bearer token for authorization
# -n NAMESPACES,                   Exclude the specified list of namespaces
#     --exclude-namespace
# -i NAMESPACES,                   Include the specified list of namespaces, an
#     --include-namespace          empty list includes all namespaces
#     --exclude-nodes              Exclude the specified nodes (comma separated list)
#                                  Exclude wins when a node is in both include and exclude lists
#     --include-nodes              Include the specified nodes (comma separated list), an
#                                  empty list includes all nodes
# -f, --filter FILTER              Selector filter for cronjobs to be checked
# -c, --cronjobs CRONJOBS                  Optional list of cronjobs to check.
#                                  Defaults to 'all'
#
# NOTES:
# => The filter used for the -f flag is in the form key=value. If multiple
#    filters need to be specfied, use a comma. ex. foo=bar,red=color
#
# LICENSE:
#   Barry Martin <nyxcharon@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugins-kubernetes/cli'
require 'sensu-plugins-kubernetes/exclude'

class AllcronjobsAreReady < Sensu::Plugins::Kubernetes::CLI
  @options = Sensu::Plugins::Kubernetes::CLI.options.dup
  include Sensu::Plugins::Kubernetes::Exclude

  option :cronjob_list,
         description: 'List of cronjobs to check',
         short: '-c CRONJOBS',
         long: '--cronjobs',
         default: 'all'

  option :cronjob_filter,
         description: 'Selector filter for cronjobs to be checked',
         short: '-f FILTER',
         long: '--filter'

  option :exclude_namespace,
         description: 'Exclude the specified list of namespaces',
         short: '-n NAMESPACES',
         long: '--exclude-namespace',
         proc: proc { |a| a.split(',') },
         default: ''

  option :include_namespace,
         description: 'Include the specified list of namespaces',
         short: '-i NAMESPACES',
         long: '--include-namespace',
         proc: proc { |a| a.split(',') },
         default: ''

  option :exclude_nodes,
         description: 'Exclude the specified nodes (comma separated list)',
         long: '--exclude-nodes NODES',
         proc: proc { |a| a.split(',') },
         default: ''

  option :include_nodes,
         description: 'Include the specified nodes (comma separated list)',
         long: '--include-nodes NODES',
         proc: proc { |a| a.split(',') },
         default: ''

  def run
    cronjobs_list = []
    failed_cronjobs = []
    cronjobs = []
    if config[:cronjob_filter].nil?
      cronjobs_list = parse_list(config[:cronjob_list])
      cronjobs = client.get_cronjobs
    else
      cronjobs = client.get_cronjobs(label_selector: config[:cronjob_filter].to_s)
      if cronjobs.empty?
        unknown 'The filter specified resulted in 0 cronjobs'
      end
      cronjobs_list = ['all']
    end
    cronjobs.each do |cronjob|
      next if cronjob.nil?
      next if should_exclude_namespace(cronjob.metadata.namespace)
      next if should_exclude_node(cronjob.spec.nodeName)
      next unless cronjobs_list.include?(cronjob.metadata.name) || cronjobs_list.include?('all')
      next if cronjob.status.lastScheduleTime.nil?
      # Check for overrun
      cronjob_last_run = Time.parse(cronjob.status.lastScheduleTime)
      cronjob_last_scheduled = CronParser.new(cronjob.spec.schedule).last
      puts cronjob.metadata.name
      failed_cronjobs << "#{cronjob.metadata.namespace}.#{cronjob.metadata.name}" if cronjob_last_run != cronjob_last_scheduled
    end
    if failed_cronjobs.empty?
      ok 'All cronjobs are reporting as ready'
    else
      critical "cronjobs failed: #{failed_cronjobs.join(' ')}"
    end
  rescue KubeException => e
    critical 'API error: ' << e.message
  end

  def parse_list(list)
    return list.split(',') if list && list.include?(',')
    return [list] if list
    ['']
  end

  def should_exclude_namespace(namespace)
    return !config[:include_namespace].include?(namespace) unless config[:include_namespace].empty?
    config[:exclude_namespace].include?(namespace)
  end
end
