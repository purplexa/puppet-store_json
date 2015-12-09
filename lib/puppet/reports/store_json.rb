require 'puppet'
require 'fileutils'
require 'puppet/util'
require 'json'

SEPARATOR = [Regexp.escape(File::SEPARATOR.to_s), Regexp.escape(File::ALT_SEPARATOR.to_s)].join

Puppet::Reports.register_report(:store_json) do
  desc "Store the json report on disk.  Each host sends its report as a JSON dump
    and this just stores the file on disk, in the `reportdir` directory.

    These files collect quickly -- one every half hour -- so it is a good idea
    to perform some maintenance on them if you use this report (it's the only
    default report)."

  def process
    validate_host(host)

    dir = File.join(Puppet[:reportdir], host)

    if ! Puppet::FileSystem.exist?(dir)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod_R(0750, dir)
    end

    # Now store the report.
    now = Time.now.gmtime
    name = %w{year month day hour min}.collect do |method|
      # Make sure we're at least two digits everywhere
      '%02d' % now.send(method).to_s
    end.join('') + '.json'

    file = File.join(dir, name)

    begin
      Puppet::Util.replace_file(file, 0640) do |fh|
        # Because puppet manages this in a dumb way, to_data_hash produces an object which contains references to the
        # original report object, meaning modifying this will modify the report object used by later report processors.
        jsonified = {}
        jsonified['host'] = self.host.clone
        jsonified['time'] = self.time.clone
        jsonified['configuration_version'] = self.configuration_version
        jsonified['transaction_uuid'] = self.transaction_uuid.clone
        jsonified['report_format'] = self.report_format
        jsonified['puppet_version'] = self.puppet_version.clone
        jsonified['kind'] = self.kind.clone
        jsonified['status'] = self.status.clone
        jsonified['environment'] = self.environment.clone
        jsonified['logs'] = self.logs.map do |log|
          ret = {}
          ret['file'] = log.file.clone
          ret['line'] = log.line
          ret['level'] = log.level.clone
          ret['message'] = log.message.clone
          ret['source'] = log.source.clone
          ret['time'] = log.time.clone
          ret['tags'] = log.tags.to_a.clone
        end
        jsonified['metrics'] = {}
        self.metrics.each do |key, value|
          jsonified['metrics'][key] = {}
          jsonified['metrics'][key]['name'] = value.name.clone
          jsonified['metrics'][key]['label'] = value.label.clone
          jsonified['metrics'][key]['values'] = value.values.clone
        end
        jsonified['resource_statuses'] = {}
        self.resource_statuses.each do |key, value|
          jsonified['resource_statuses'][key]['resource_type'] = value.resource_type.clone
          jsonified['resource_statuses'][key]['title'] = value.title.clone
          jsonified['resource_statuses'][key]['resource'] = value.resource.clone
          jsonified['resource_statuses'][key]['file'] = value.file.clone
          jsonified['resource_statuses'][key]['line'] = value.line
          jsonified['resource_statuses'][key]['evaluation_time'] = value.evaluation_time.clone
          jsonified['resource_statuses'][key]['change_count'] = value.change_count
          jsonified['resource_statuses'][key]['out_of_sync_count'] = value.out_of_sync_count
          jsonified['resource_statuses'][key]['time'] = value.time.clone
          jsonified['resource_statuses'][key]['out_of_sync'] = value.out_of_sync.clone
          jsonified['resource_statuses'][key]['changed'] = value.changed.clone
          jsonified['resource_statuses'][key]['skipped'] = value.skipped.clone
          jsonified['resource_statuses'][key]['failed'] = value.failed.clone
          jsonified['resource_statuses'][key]['containment_path'] = value.containment_path.clone
          jsonified['resource_statuses'][key]['tags'] = value.tags.to_a.clone
          jsonified['resource_statuses'][key]['events'] = value.events.map do |event|
            tmp = {}
            tmp['audited'] = event.audited.clone
            tmp['property'] = event.property.clone
            tmp['previous_value'] = event.previous_value.clone
            tmp['desired_value'] = event.desired_value.clone
            tmp['historical_value'] = event.historical_value.clone
            tmp['message'] = event.message.clone
            tmp['name'] = event.name.clone
            tmp['status'] = event.status.clone
            tmp['time'] = event.time.clone
            tmp
          end
        end
        fh.print(JSON.generate(jsonified))
      end
    rescue => detail
       Puppet.log_exception(detail, "Could not write report for #{host} at #{file}: #{detail}")
    end

    # Only testing cares about the return value
    file
  end

  # removes all reports for a given host?
  def self.destroy(host)
    validate_host(host)

    dir = File.join(Puppet[:reportdir], host)

    if Puppet::FileSystem.exist?(dir)
      Dir.entries(dir).each do |file|
        next if ['.','..'].include?(file)
        file = File.join(dir, file)
        Puppet::FileSystem.unlink(file) if File.file?(file)
      end
      Dir.rmdir(dir)
    end
  end

  def validate_host(host)
    if host =~ Regexp.union(/[#{SEPARATOR}]/, /\A\.\.?\Z/)
      raise ArgumentError, "Invalid node name #{host.inspect}"
    end
  end
  module_function :validate_host
end
