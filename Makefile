TEST_DIR := /tmp/dataflow_engine_test
PARALLEL=3
GO       := GO111MODULE=on go
GOBUILD  := CGO_ENABLED=0 $(GO) build -trimpath
GOTEST := CGO_ENABLED=1 go test -p $(PARALLEL) --race
FAIL_ON_STDOUT := awk '{ print  } END { if (NR > 0) { exit 1  }  }'

PACKAGE_LIST := go list ./... | grep -vE 'proto|pb' | grep -v 'e2e'
PACKAGES := $$($(PACKAGE_LIST))
GOFILES := $$(find . -name '*.go' -type f | grep -vE 'proto|pb\.go')
FAILPOINT_DIR := $$(for p in $(PACKAGES); do echo $${p\#"github.com/hanfei1991/microcosm/"}|grep -v "github.com/hanfei1991/microcosm/"; done)
FAILPOINT := tools/bin/failpoint-ctl

FAILPOINT_ENABLE  := $$(echo $(FAILPOINT_DIR) | xargs $(FAILPOINT) enable >/dev/null)
FAILPOINT_DISABLE := $$(echo $(FAILPOINT_DIR) | xargs $(FAILPOINT) disable >/dev/null)

all: df-proto build

build: df-master df-executor df-master-client df-demo

df-proto:
	./generate-proto.sh

df-master:
	$(GOBUILD) -o bin/master ./cmd/master
	cp ./bin/master ./ansible/roles/common/files/master.bin

df-executor:
	$(GOBUILD) -o bin/executor ./cmd/executor
	cp ./bin/executor ./ansible/roles/common/files/executor.bin

df-master-client:
	$(GOBUILD) -o bin/master-client ./cmd/master-client

df-demo:
	$(GOBUILD) -o bin/demoserver ./cmd/demoserver
	cp ./bin/demoserver ./ansible/roles/common/files/demoserver.bin

df-chaos-case:
	$(GOBUILD) -o bin/df-chaos-case ./chaos/cases

unit_test: check_failpoint_ctl
	mkdir -p "$(TEST_DIR)"
	$(FAILPOINT_ENABLE)
	$(GOTEST) -cover -covermode=atomic -coverprofile="$(TEST_DIR)/cov.unit.out" $(PACKAGES) \
		|| { $(FAILPOINT_DISABLE); exit 1; }
	$(FAILPOINT_DISABLE)

tools_setup:
	@echo "setup build and check tools"
	@cd tools && make

tools/bin/failpoint-ctl: tools/go.mod
	cd tools && $(GO) build -mod=mod -o ./bin/failpoint-ctl github.com/pingcap/failpoint/failpoint-ctl

check_failpoint_ctl: tools/bin/failpoint-ctl

failpoint-enable: check_failpoint_ctl
	$(FAILPOINT_ENABLE)

failpoint-disable: check_failpoint_ctl
	$(FAILPOINT_DISABLE)

check: tools_setup lint fmt tidy

fmt:
	@echo "gofmt (simplify)"
	tools/bin/gofumports -l -w $(GOFILES) 2>&1 | $(FAIL_ON_STDOUT)
	@echo "run shfmt"
	tools/bin/shfmt -d -w .

tidy:
	@echo "check go mod tidy"
	go mod tidy

lint:
	echo "golangci-lint"; \
	tools/bin/golangci-lint run --config=./.golangci.yml --timeout 10m0s --skip-files "pb"

kvmock: tools_setup
	tools/bin/mockgen github.com/hanfei1991/microcosm/pkg/meta/metaclient KVClient \
	> pkg/meta/kvclient/mock/mockclient.go
