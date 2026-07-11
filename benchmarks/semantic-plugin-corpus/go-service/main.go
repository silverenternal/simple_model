package main

import "net/http"

func StartServer() {}
func privateHelper() {}
func main() { http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {}) }
