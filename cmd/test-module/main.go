// Package main is a generic-service module whose startup can be made slow or
// to crash through env vars, for exercising module status in the app.
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
	if delay, err := strconv.Atoi(os.Getenv("START_DELAY_SEC")); err == nil && delay > 0 {
		fmt.Fprintf(os.Stderr, "START_DELAY_SEC=%d, sleeping before serving\n", delay)
		time.Sleep(time.Duration(delay) * time.Second)
	}
	if os.Getenv("CRASH_ON_START") == "1" {
		fmt.Fprintln(os.Stderr, "CRASH_ON_START=1, exiting")
		os.Exit(1)
	}

	model := resource.NewModel(namespace, "test-module", "noop")
	resource.RegisterService(genericservice.API, model, resource.Registration[resource.Resource, resource.NoNativeConfig]{
		Constructor: newNoop,
	})
	module.ModularMain(resource.APIModel{API: genericservice.API, Model: model})
}

type noop struct {
	resource.Named
	resource.TriviallyReconfigurable
	resource.TriviallyCloseable
}

func newNoop(
	_ context.Context, _ resource.Dependencies, conf resource.Config, _ logging.Logger,
) (resource.Resource, error) {
	return &noop{Named: conf.ResourceName().AsNamed()}, nil
}

func (*noop) DoCommand(context.Context, map[string]interface{}) (map[string]interface{}, error) {
	return map[string]interface{}{}, nil
}
