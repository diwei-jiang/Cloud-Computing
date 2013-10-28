require 'aws-sdk'

config_file = './config.yml'
config = YAML.load(File.read(config_file))

AWS.config(config)


cw = AWS::CloudWatch.new(:region => "us-west-2")
as = AWS::AutoScaling.new(:region => "us-west-2")

# as.groups['ass1-group'].ec2_instances.each do |ins|
#   p ins.status
# end
# as.groups['ass1-group'].update(:min_size => 0)
# p as.groups['ass1-group'].min_size
# exit

cw.alarms['HighCpuAlarm'].delete
cw.alarms['LowCpuAlarm'].delete

if as.groups['ass1-group'].exists?
  as.groups['ass1-group'].delete
end

if as.launch_configurations['ass1-config'].exists?
  as.launch_configurations['ass1-config'].delete
end