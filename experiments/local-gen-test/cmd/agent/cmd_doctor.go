package main

import (
	"fmt"
	"os"
	"runtime"
)

func runDoctor() {
	wd, err := os.Getwd()
	if err != nil {
		wd = "(unknown)"
	}
	fmt.Printf("go:  %s\n", runtime.Version())
	fmt.Printf("dir: %s\n", wd)
}
