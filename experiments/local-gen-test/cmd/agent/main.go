package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: agent <command>")
		os.Exit(1)
	}
	switch os.Args[1] {
	case "version":
		runVersion()
	case "doctor":
		runDoctor()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}
