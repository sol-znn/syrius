package pillar

import (
	"testing"
	"time"

	"github.com/zenon-network/go-zenon/chain/nom"
	"github.com/zenon-network/go-zenon/common"
	"github.com/zenon-network/go-zenon/consensus"
	"github.com/zenon-network/go-zenon/protocol"
	"github.com/zenon-network/go-zenon/wallet"
)

type closedProducerBroadcaster struct {
	t         *testing.T
	syncCalls int
}

func (b *closedProducerBroadcaster) SyncInfo() *protocol.SyncInfo {
	b.syncCalls++
	return &protocol.SyncInfo{State: protocol.SyncDone}
}

func (b *closedProducerBroadcaster) CreateMomentum(*nom.MomentumTransaction, *nom.DetailedMomentum) {
	b.t.Fatal("closed producer must not broadcast a momentum")
}

func (b *closedProducerBroadcaster) CreateAccountBlock(*nom.AccountBlockTransaction) error {
	b.t.Fatal("closed producer must not broadcast an account block")
	return nil
}

func TestClosedWorkerProducerEventStopsWithoutTask(t *testing.T) {
	w := &worker{log: common.PillarLogger}
	if err := w.Start(); err != nil {
		t.Fatal(err)
	}
	if err := w.Stop(); err != nil {
		t.Fatal(err)
	}
	now := common.Clock.Now()
	event := consensus.ProducerEvent{
		StartTime: now.Add(-time.Minute),
		EndTime:   now.Add(time.Minute),
	}
	if task := w.Process(event); task != nil {
		t.Fatal("closed worker must decline the event")
	}
	broadcaster := &closedProducerBroadcaster{t: t}
	m := &manager{
		log:         common.PillarLogger,
		coinbase:    &wallet.KeyPair{},
		worker:      w,
		broadcaster: broadcaster,
	}
	// A consensus callback can already be scheduled when Stop closes the
	// worker. Exercise its actual supervisor after that close, without a
	// mocked task or asynchronous test completion hiding the panic.
	m.processSupervised(event)
	if broadcaster.syncCalls != 1 {
		t.Fatalf("producer admission was not exercised: %d", broadcaster.syncCalls)
	}
}
