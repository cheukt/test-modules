// Package main is a generic-service module that can be made to start slowly, crash, log errors,
// or fail to build its resources, for exercising module status in the app. See README.md.
package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"time"

	"go.viam.com/rdk/logging"
	"go.viam.com/rdk/module"
	"go.viam.com/rdk/resource"
	genericservice "go.viam.com/rdk/services/generic"
)

// namespace is set at build time (-ldflags "-X main.namespace=...") so the model matches the uploading org.
var namespace = "local"

func main() {
	// viam-server logs module stderr at error level under the module's logger.
	if interval := envSeconds("LOG_ERROR_INTERVAL_SEC"); interval > 0 {
		go func() {
			for range time.Tick(interval) {
				fmt.Fprintln(os.Stderr, "LOG_ERROR_INTERVAL_SEC: module error")
			}
		}()
	}
	if delay := envSeconds("START_DELAY_SEC"); delay > 0 {
		fmt.Fprintf(os.Stderr, "START_DELAY_SEC: sleeping %s before serving\n", delay)
		time.Sleep(delay)
	}
	if os.Getenv("CRASH_ON_START") == "1" {
		crash("CRASH_ON_START=1")
	}
	if after := envSeconds("CRASH_AFTER_SEC"); after > 0 {
		go func() {
			time.Sleep(after)
			crash("CRASH_AFTER_SEC elapsed")
		}()
	}

	model := resource.NewModel(namespace, "test-module", "noop")
	resource.RegisterService(genericservice.API, model, resource.Registration[resource.Resource, resource.NoNativeConfig]{
		Constructor: newNoop,
	})
	module.ModularMain(resource.APIModel{API: genericservice.API, Model: model})
}

func envSeconds(key string) time.Duration {
	secs, err := strconv.ParseFloat(os.Getenv(key), 64)
	if err != nil || secs <= 0 {
		return 0
	}
	return time.Duration(secs * float64(time.Second))
}

func seconds(secs float64) time.Duration {
	return time.Duration(secs * float64(time.Second))
}

func crash(reason string) {
	fmt.Fprintf(os.Stderr, "%s, exiting\n", reason)
	os.Exit(1)
}

type noop struct {
	resource.Named
	resource.AlwaysRebuild
	closeDelay time.Duration
	cancel     context.CancelFunc
}

func newNoop(
	_ context.Context, _ resource.Dependencies, conf resource.Config, logger logging.Logger,
) (resource.Resource, error) {
	attrs := conf.Attributes
	time.Sleep(seconds(attrs.Float64("build_delay_sec", 0)))
	if attrs.Bool("crash_on_build", false) {
		crash(conf.Name + ": crash_on_build is set")
	}
	if attrs.Bool("fail_build", false) {
		return nil, fmt.Errorf("%s: fail_build is set", conf.Name)
	}

	ctx, cancel := context.WithCancel(context.Background())
	if interval := seconds(attrs.Float64("error_log_interval_sec", 0)); interval > 0 {
		go func() {
			ticker := time.NewTicker(interval)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					logger.Error("error_log_interval_sec: resource error")
				}
			}
		}()
	}
	return &noop{
		Named:      conf.ResourceName().AsNamed(),
		closeDelay: seconds(attrs.Float64("close_delay_sec", 0)),
		cancel:     cancel,
	}, nil
}

func (n *noop) DoCommand(_ context.Context, cmd map[string]interface{}) (map[string]interface{}, error) {
	if shouldCrash, _ := cmd["crash"].(bool); shouldCrash {
		crash("crash command")
	}
	return map[string]interface{}{}, nil
}

func (n *noop) Close(context.Context) error {
	n.cancel()
	time.Sleep(n.closeDelay)
	return nil
}
