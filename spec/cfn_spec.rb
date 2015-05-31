require 'spec_helper'

describe Cfer::Cfn::Client do
  cfn = Cfer::Cfn::Client.new stack_name: 'test', region: 'us-east-1'

  it 'creates stacks' do
    stack = create_stack key: 'value', remote_key: '@other_stack.value' do
      parameter :key
      parameter :remote_key
      parameter :remote_default, Default: '@other_stack.value'
    end

    expect(cfn).to receive(:validate_template)
      .exactly(1).times
      .with(template_body: stack.to_cfn) {
      double(
        capabilities: [],
        parameters: [
          double(parameter_key: 'key', no_echo: false),
          double(parameter_key: 'remote_key', no_echo: false),
          double(parameter_key: 'remote_default', no_echo: false, default_value: '@other_stack.value')
        ]
      )
    }

    expect(cfn).to receive(:describe_stacks)
      .exactly(1).times
      .with(stack_name: 'other_stack')
      .and_return(
        double(stacks: double(first: double(outputs: [
          double(output_key: 'value', output_value: 'remote_value')
        ])))
      )

    expect(cfn).to receive(:create_stack)
      .exactly(1).times
      .with(
        stack_name: 'test',
        template_body: stack.to_cfn,
        parameters: [
          { :ParameterKey => 'key', :ParameterValue => 'value', :UsePreviousValue => false },
          { :ParameterKey => 'remote_key', :ParameterValue => 'remote_value', :UsePreviousValue => false },
          { :ParameterKey => 'remote_default', :ParameterValue => 'remote_value', :UsePreviousValue => false }
        ],
        capabilities: []
      )

    cfn.converge stack
  end

  it 'updates stacks' do
    stack = create_stack do
      parameter :key
      parameter :remote_key
      parameter :remote_default, Default: '@other_stack.value'
    end

    expect(cfn).to receive(:validate_template)
      .exactly(1).times
      .with(template_body: stack.to_cfn) {
        double(
          capabilities: [],
          parameters: [
            double(parameter_key: 'key', no_echo: false, default_value: nil),
            double(parameter_key: 'remote_key', no_echo: false, default_value: nil),
            double(parameter_key: 'remote_default', no_echo: false, default_value: '@other_stack.value')
          ]
        )
      }

    expect(cfn).to receive(:describe_stacks)
      .exactly(1).times
      .with(stack_name: 'other_stack')
      .and_return(
        double(stacks: double(first: double(outputs: [
          double(output_key: 'value', output_value: 'new_remote_value')
        ])))
      )

    stack_options = {
      stack_name: 'test',
      template_body: stack.to_cfn,
      parameters: [
        { :ParameterKey => 'key', :UsePreviousValue => true },
        { :ParameterKey => 'remote_key', :UsePreviousValue => true },
        { :ParameterKey => 'remote_default', :ParameterValue => 'new_remote_value', :UsePreviousValue => false }
      ],
      capabilities: []
    }
    
    expect(cfn).to receive(:create_stack)
      .exactly(1).times
      .with(stack_options)
      .and_raise(Cfer::Util::StackExistsError)

    expect(cfn).to receive(:update_stack)
      .exactly(1).times
      .with(stack_options)

    cfn.converge stack
  end

  it 'follows logs' do
    cfn = Cfer::Cfn::Client.new stack_name: 'test', region: 'us-east-1'

    event_list = [
      double('event 1', event_id: 1, timestamp: DateTime.now, resource_status: 'TEST', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'abcd'),
      double('event 2', event_id: 2, timestamp: DateTime.now, resource_status: 'TEST2', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'efgh'),
      double('event 3', event_id: 3, timestamp: DateTime.now, resource_status: 'TEST3', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'abcd'),
      double('event 4', event_id: 4, timestamp: DateTime.now, resource_status: 'TEST4', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'efgh'),
      double('event 5', event_id: 5, timestamp: DateTime.now, resource_status: 'TEST5', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'abcd'),
      double('event 6', event_id: 6, timestamp: DateTime.now, resource_status: 'TEST_COMPLETE', resource_type: 'Cfer::TestResource', logical_resource_id: 'test_resource', resource_status_reason: 'efgh')
    ]

    expect(cfn).to receive(:describe_stack_events)
      .exactly(3).times
      .with(stack_name: 'test')
      .and_return(
        double(stack_events: event_list.take(2).reverse),
        double(stack_events: event_list.take(4).reverse),
        double(stack_events: event_list.take(6).reverse)
      )

    expect(cfn).to receive(:describe_stacks)
      .exactly(2).times
      .with(stack_name: 'test')
      .and_return(
        double(stacks: [ double(stack_status: 'a status') ]),
        double(stacks: [ double(stack_status: 'TEST_COMPLETE')])
      )

    yielder = double('yield receiver')
    event_list.drop(1).each do |event|
      expect(yielder).to receive(:yielded).with(event)
    end

    cfn.tail(number: 1, follow: true, no_sleep: true) do |event|
      yielder.yielded event
    end

  end
end
