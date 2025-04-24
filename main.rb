require 'anthropic'
require 'erb'
require 'json-schema'
# require 'byebug' # if ENV['DEBUG']

SYSTEM_PROMPT = <<~PROMPT.gsub("\n", ' ')
  You are an expert software architect decades of experience. You particularly excel in
  creating cost-effective, performant, and resiliant architectures with a simplicity that
  would not be obvious to the average software engineer. You're also very good at
  explaining your ideas with entity relationship diagrams, sequence diagrams,
  and flow charts. You're particularly skilled in the Mermaid diagraming tool, with deep knowledge
  of the grammar for each kind of the charts it supports:
  Flowchart, Sequence Diagram, Class Diagram, State Diagram,
  Entity Relationship Diagram, User Journey, Gantt, Pie Chart, Quadrant chart, Requirement
  Diagram, Gitgraph (git) Diagram, C4 Diagram, Mindmaps, Timeline, ZenUML, Sankey, XY Chart,
  Block Diagram, Packet, Kanban, Architecture, and Radar.
PROMPT

JSON_SCHEMA = {
  "type": 'object',
  "required": %w[overallReasoning diagrams],
  "properties": {
    "threeWordUserRequestDescription": {
      "type": 'string'
    },
    "overallReasoning": {
      "type": 'string'
    },
    "diagrams": {
      "type": 'array',
      "items": {
        "type": 'object',
        "required": %w[mermaid reasoning],
        "properties": {
          "mermaid": {
            "type": 'string'
          },
          "reasoning": {
            "type": 'string'
          }
        },
        "additionalProperties": false
      }
    }
  },
  "additionalProperties": false
}.freeze

# Raised if API key not set
class AnthropicApiKeyNotSetError < StandardError; end

class Database
  DIR = 'db'.freeze
end

anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY') do
  raise AnthropicApiKeyNotSetError
end

Anthropic.configure do |config|
  config.access_token = anthropic_api_key
  config.log_errors = true
end

client = Anthropic::Client.new

prompt_template = File.read('./prompt.erb')

# Context for prompt template
Context = Struct.new(:user_request) do
  def this
    binding
  end

  def json_schema
    JSON_SCHEMA
  end
end

prompt_template_erb = ERB.new(prompt_template)

puts 'What kind of architecture can I build for you?'
puts

user_request = ''

while (line = gets)
  user_request += line
end

puts 'one moment'

context = Context.new(user_request:)

user_content = prompt_template_erb.result(context.this)

require 'fileutils'
bucket = Digest::MD5.hexdigest(user_request)
bucket_dir = File.join(Database::DIR, bucket)

messages_dir = File.join(bucket_dir, 'messages')

FileUtils.mkdir_p(bucket_dir)
FileUtils.mkdir_p messages_dir

File.open(File.join(bucket_dir, 'user-request'), 'w') do |file|
  file.write(user_request)
end

messages = []
responses = []

loop do
  messages += [
    { 'role' => 'user', 'content' => [{ 'type' => 'text', 'text' => user_content }] },
    { 'role' => 'assistant', 'content' => [{ 'type' => 'text', 'text' => '{' }] }
  ]

  [messages.count - 2, messages.count - 1].each do |i|
    message_name = File.join(messages_dir, i.to_s)
    File.open(message_name, 'w') do |file|
      file.write(JSON.dump(messages[i]))
    end
  end

  puts messages

  response = client.messages(
    parameters: {
      model: 'claude-3-7-sonnet-20250219',
      system: SYSTEM_PROMPT,
      messages:,
      max_tokens: 4096
    }
  )

  responses += [response]

  messages += [response]

  message_file_name = File.join(messages_dir, (messages.count - 1).to_s)

  File.open(message_file_name, 'w') { |file| file.write(JSON.dump(messages.last)) }

  raw_json = messages.last(2).inject('') do |acc, message|
    acc + message['content'].first['text']
  end

  begin
    json = JSON.parse(raw_json)
  rescue JSON::Schema::JsonParseError
    warn "Could not parse Claude response: #{raw_json}"
    return
  end

  errors = JSON::Validator.fully_validate(JSON_SCHEMA, json)

  if errors.any?
    warn "could not validate response JSON: #{errors.inspect}"
    return
  end

  description_file_name = File.join(bucket_dir, 'description')
  description = json['threeWordUserRequestDescription']

  File.open(description_file_name, 'w') { |file| file.write(description) }

  overall_reasoning = json['overallReasoning']

  puts 'Reasoning:'
  puts bucket
  puts overall_reasoning

  diagrams = json['diagrams']

  diagrams_dir = File.join(bucket_dir, 'diagrams', responses.count.to_s)

  FileUtils.mkdir_p(diagrams_dir)

  diagrams.each do |diagram|
    # Write mermaid file
    mermaid = diagram['mermaid']
    hash = Digest::MD5.hexdigest(mermaid)
    mermaid_file_name = File.join(diagrams_dir, "#{hash}.mmd")
    File.open(mermaid_file_name, 'w') do |file|
      file.write(mermaid)
    end

    image_file_name = File.join(diagrams_dir, "#{hash}.svg")

    # Generate mermaid diagram
    unless system('mmdc', '-i', mermaid_file_name, '-o', image_file_name, '-e', 'svg')
      warn 'Error generating mermaid diagram!'
    end

    system('open', image_file_name)

    puts hash
    puts diagram['reasoning']
  end

  prompt_template_erb = ERB.new(prompt_template)

  puts 'What else?'
  puts

  user_request = $stdin.gets.chomp

  puts 'one moment'

  context = Context.new(user_request:)

  user_content = prompt_template_erb.result(context.this)
end
