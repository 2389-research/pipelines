package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		printUsage(os.Stderr)
		os.Exit(1)
	}
	switch os.Args[1] {
	case "version":
		runVersion()
	case "doctor":
		runDoctor()
	case "tui":
		runTUI(os.Stdout)
	case "serve":
		runServe(os.Stdout)
	case "run":
		runRun(os.Stdout)
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, "agent <command>")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Available commands:")
	fmt.Fprintln(w, "  tui      launch terminal UI")
	fmt.Fprintln(w, "  serve    start HTTP/SSE server")
	fmt.Fprintln(w, "  run      headless session execution")
	fmt.Fprintln(w, "  doctor   environment diagnostics")
	fmt.Fprintln(w, "  version  print version")
}
