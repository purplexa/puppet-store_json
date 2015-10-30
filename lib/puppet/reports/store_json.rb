require 'puppet'
require 'fileutils'
require 'puppet/util'
require 'json'

SEPARATOR = [Regexp.escape(File::SEPARATOR.to_s), Regexp.escape(File::ALT_SEPARATOR.to_s)].join

Puppet::Reports.register_report(:store) do
  desc "Store the yaml report on disk.  Each host sends its report as a YAML dump
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
      "%02d" % now.send(method).to_s
    end.join("") + ".json"

    file = File.join(dir, name)

    begin
      Puppet::Util.replace_file(file, 0640) do |fh|
        jsonified = self.to_data_hash
        if jsonified['logs'].first.respond_to? :to_data_hash
          jsonified['logs'] = jsonified['logs'].map do |log|
            newlog = log.to_data_hash
            if log.tags.respond_to? :to_data_hash
              newlog['tags'] = log.tags.to_data_hash
            end
            newlog
          end
        end
        if jsonified['metrics'].values.first.respond_to? :to_data_hash
          jsonified['metrics'].each { |k,v| jsonified['metrics'][k] = v.to_data_hash }
        end
        if jsonified['resource_statuses'].values.first.respond_to? :to_data_hash
          jsonified['resource_statuses'].each do |k,v|
            jsonified['resource_statuses'][k] = v.to_data_hash
            if v.events.first.respond_to? :to_data_hash
              jsonified['resource_statuses'][k]['events'] = v.events.map { |x| x.to_data_hash }
            end
            if v.tags.respond_to? :to_data_hash
              jsonified['resource_statuses'][k]['tags'] = v.tags.to_data_hash
            end
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
