#! /usr/bin/env ruby
#
#   check-kube-jobs-failed
#
# DESCRIPTION:
# => Check if are running, successful, or failed
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
# -f, --filter FILTER              Selector filter for jobs to be checked
# -c, --jobs JOBS                  Optional list of jobs to check.
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

class AlljobsAreReady < Sensu::Plugins::Kubernetes::CLI
  @options = Sensu::Plugins::Kubernetes::CLI.options.dup
  include Sensu::Plugins::Kubernetes::Exclude

  option :job_list,
         description: 'List of jobs to check',
         short: '-c JOBS',
         long: '--jobs',
         default: 'all'

  option :job_filter,
         description: 'Selector filter for jobs to be checked',
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
    jobs_list = []
    failed_jobs = []
    jobs = []
    if config[:job_filter].nil?
      jobs_list = parse_list(config[:job_list])
      jobs = client.get_jobs
    else
      jobs = client.get_jobs(label_selector: config[:job_filter].to_s)
      if jobs.empty?
        unknown 'The filter specified resulted in 0 jobs'
      end
      jobs_list = ['all']
    end
    jobs.each do |job|
      next if job.nil?
      next if should_exclude_namespace(job.metadata.namespace)
      next if should_exclude_node(job.spec.nodeName)
      next unless jobs_list.include?(job.metadata.name) || jobs_list.include?('all')
      # Check for failed state
      next unless job.status.failed == 1
      job_stamp = Time.parse(job.metadata.creationTimestamp)
      puts job.metadata.name
      failed_jobs << "#{job.metadata.namespace}.#{job.metadata.name}"
    end
    if failed_jobs.empty?
      ok 'All jobs are reporting as ready'
    else
      critical "jobs failed: #{failed_jobs.join(' ')}"
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
