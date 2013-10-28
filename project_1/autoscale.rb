# 
# author: djiango
# 
require 'aws-sdk'

config_file = './config.yml'
config = YAML.load(File.read(config_file))

AWS.config(config)

cw = AWS::CloudWatch.new(:region => "us-west-2")
as = AWS::AutoScaling.new(:region => "us-west-2")

launch_config = group = nil

# create a config
unless (launch_config = as.launch_configurations['ass1-config']).exists?
launch_config = as.launch_configurations.create(
  'ass1-config', 'ami-70f96e40', 't1.micro')
end


# create group
unless (group = as.groups['ass1-group']).exists?
group = as.groups.create('ass1-group',
  :launch_configuration => launch_config,
  :availability_zones => ['us-west-2a', 'us-west-2b'],
  :min_size => 1,
  :max_size => 4)
end

# create scale up policy
policyScaleUp = group.scaling_policies.create('scale-up-policy',
  :scaling_adjustment => 1,
  :adjustment_type => 'ChangeInCapacity',
  :cooldown => 30)

# create High Cpu Alarm
cw.alarms.create('HighCpuAlarm',
  :comparison_operator => 'GreaterThanThreshold',
  :evaluation_periods => 1,
  :metric_name => 'CPUUtilization',
  :namespace => 'AWS/EC2',
  :period => 60,
  :statistic => 'Average',
  :threshold => 30,
  :alarm_actions => [policyScaleUp.arn],
  :dimensions => [{:name => 'AutoScalingGroupName',
                  :value => 'ass1-group'}])

# create scale down policy
policyScaleDown = group.scaling_policies.create('scale-down-policy',
  :scaling_adjustment => -1,
  :adjustment_type => 'ChangeInCapacity',
  :cooldown => 30)

# create Low Cpu Alarm
cw.alarms.create('LowCpuAlarm',
  :comparison_operator => 'LessThanThreshold',
  :evaluation_periods => 1,
  :metric_name => 'CPUUtilization',
  :namespace => 'AWS/EC2',
  :period => 60,
  :statistic => 'Average',
  :threshold => 10,
  :alarm_actions => [policyScaleDown.arn],
  :dimensions => [{:name => 'AutoScalingGroupName',
                  :value => 'ass1-group'}])


