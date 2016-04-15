# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/kafka"

java_import "java.util.Properties"                                                                                      
java_import "kafka.server.KafkaConfig"
java_import "kafka.server.KafkaServerStartable"
java_import "org.apache.kafka.clients.producer.KafkaProducer"
java_import "org.apache.kafka.clients.producer.ProducerRecord"
java_import "org.apache.zookeeper.server.ServerConfig"
java_import "org.apache.zookeeper.server.ZooKeeperServerMain"
java_import "org.apache.zookeeper.server.quorum.QuorumPeerConfig"

def start_kafka()
  # org.apache.log4j.BasicConfigurator.configure()
  `rm -rf /tmp/kafka-logs /tmp/zookeeper`
  zk_props = Properties.new
  zk_props.set_property("dataDir", "/tmp/zookeeper")
  zk_props.set_property("clientPort", "2181")
  zk = ZooKeeperServerMain.new
  quorum_configuration = QuorumPeerConfig.new
  quorum_configuration.parse_properties(zk_props)
  config = ServerConfig.new
  config.read_from(quorum_configuration)

  Thread.new do
    zk.run_from_config(config)
  end

  kafka_props = Properties.new
  kafka_props.set_property("zookeeper.connect", "localhost:2181")
  kafka_props.set_property("broker.id", "0")
  kafka_config = KafkaConfig.new(kafka_props)
  server = KafkaServerStartable.new(kafka_config)
  server.startup

  producer_props = Properties.new
  producer_props.put("bootstrap.servers", "localhost:9092")
  producer_props.put("acks", "all")
  producer_props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer")
  producer_props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer")
  producer = KafkaProducer.new(producer_props)
  10000.times do |i|
    producer.send(ProducerRecord.new("test", i.to_s, i.to_s))
  end
  producer.close

  server
end

def stop_kafka(server)
  server.shutdown
  server.await_shutdown
end

describe "input/kafka", :integration => true do
  let(:config) do
    {
      'zk_connect' => 'localhost:2181',
      'auto_offset_reset' => 'smallest',
      'topic_id' => 'test',
      'consumer_threads' => 1
    }
  end

  subject { LogStash::Inputs::Kafka.new(config) }

  context "kafka is running" do
    before { @server = start_kafka }
    after { stop_kafka(@server) }

    it "should work" do
      subject.register
      q = Queue.new
      Thread.new do
        while q.size < 10000; end
        subject.do_stop
      end
      subject.run(q)
      expect(q.size).to eq(10000)
    end
  end

  context "kafka and zookeeper not started" do
    it "should stop and throw exception on zk-timeout" do
      subject.register
      q = Queue.new
      Thread.new do
        sleep Random.rand(1..8)
        subject.do_stop
      end
      begin
        subject.run(q)
      rescue => e
        expect("#{e}").to eq("Unable to connect to zookeeper server within timeout: 6000")
      end
    end
  end
end
