package kafka

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"go.uber.org/zap"

	"github.com/kushin77/nexus-engine/pkg/discovery"
)

// Producer publishes NexusDiscoveryEvent to Kafka
type Producer struct {
	producer *kafka.Producer
	logger   *zap.Logger
}

// NewProducer creates a new Kafka producer
func NewProducer(brokers string, logger *zap.Logger) (*Producer, error) {
	p, err := kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers": brokers,
		"acks":              "all",
		"retries":           3,
		"linger.ms":         100, // batch for 100ms or until full
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create producer: %w", err)
	}

	// Delivery reports
	go func() {
		for e := range p.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					logger.Error("delivery failed",
						zap.String("topic", *ev.TopicPartition.Topic),
						zap.Error(ev.TopicPartition.Error),
					)
				}
			case kafka.Error:
				logger.Error("kafka error", zap.Error(ev))
			}
		}
	}()

	return &Producer{producer: p, logger: logger}, nil
}

// PublishDiscoveryEvent publishes a normalized event to nexus.discovery.raw
func (p *Producer) PublishDiscoveryEvent(ctx context.Context, event *discovery.NexusDiscoveryEvent) error {
	key := fmt.Sprintf("%s-%s", event.Source, event.Id)
	value, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	msg := &kafka.Message{
		TopicPartition: kafka.TopicPartition{
			Topic:     toStrPtr("nexus.discovery.raw"),
			Partition: kafka.PartitionAny,
		},
		Key:   []byte(key),
		Value: value,
	}

	err = p.producer.Produce(msg, nil)
	if err != nil {
		return fmt.Errorf("failed to produce message: %w", err)
	}

	p.logger.Debug("published discovery event",
		zap.String("source", event.Source),
		zap.String("repo", event.Repo),
		zap.String("status", event.Status),
	)

	return nil
}

// Close gracefully shuts down the producer
func (p *Producer) Close() {
	remaining := p.producer.Flush(5000) // Wait 5s for pending messages
	if remaining > 0 {
		p.logger.Warn("messages left in queue after flush", zap.Int("count", remaining))
	}
	p.producer.Close()
}

func toStrPtr(s string) *string {
	return &s
}
