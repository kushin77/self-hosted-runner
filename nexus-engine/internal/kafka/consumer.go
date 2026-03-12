package kafka

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"go.uber.org/zap"

	"github.com/kushin77/nexus-engine/pkg/discovery"
)

// Consumer reads NexusDiscoveryEvent from Kafka topics
type Consumer struct {
	consumer *kafka.Consumer
	logger   *zap.Logger
}

// NewConsumer creates a new Kafka consumer
func NewConsumer(brokers, groupID string, topics []string, logger *zap.Logger) (*Consumer, error) {
	c, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers": brokers,
		"group.id":          groupID,
		"auto.offset.reset": "earliest",
		"isolation.level":   "read_committed", // read only committed msgs
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create consumer: %w", err)
	}

	err = c.SubscribeTopics(topics, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to subscribe to topics: %w", err)
	}

	return &Consumer{consumer: c, logger: logger}, nil
}

// Messages returns a channel of events from Kafka
func (c *Consumer) Messages(ctx context.Context) (<-chan *discovery.NexusDiscoveryEvent, <-chan error) {
	msgChan := make(chan *discovery.NexusDiscoveryEvent, 100)
	errChan := make(chan error, 10)

	go func() {
		defer close(msgChan)
		defer close(errChan)

		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			msg, err := c.consumer.ReadMessage(100 * 1e6) // 100ms timeout
			if err != nil {
				// Timeout is expected, not an error
				if kafkaErr, ok := err.(kafka.Error); ok && kafkaErr.Code() == kafka.ErrTimedOut {
					continue
				}
				errChan <- fmt.Errorf("consumer error: %w", err)
				continue
			}

			var event discovery.NexusDiscoveryEvent
			if err := json.Unmarshal(msg.Value, &event); err != nil {
				c.logger.Error("failed to unmarshal event", zap.Error(err))
				errChan <- fmt.Errorf("unmarshal error: %w", err)
				continue
			}

			select {
			case msgChan <- &event:
			case <-ctx.Done():
				return
			}
		}
	}()

	return msgChan, errChan
}

// Close gracefully shuts down the consumer
func (c *Consumer) Close() error {
	return c.consumer.Close()
}
