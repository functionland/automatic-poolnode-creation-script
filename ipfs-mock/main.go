package main

import (
	"encoding/json"
	"log"
	"net/http"
)

// Define the response structures as per your code
type PinListResp struct {
	PinLsList struct {
		Keys map[string]pinListKeysType `json:"Keys,omitempty"`
	} `json:"PinLsList"`
}

type pinListKeysType struct {
	Type string
}

type RepoInfo struct {
	NumObjects uint64   `json:"NumObjects"`
	RepoPath   string   `json:"RepoPath"`
	SizeStat   SizeStat `json:"SizeStat"`
	Version    string   `json:"Version"`
	RepoSize   uint64   `json:"RepoSize"`
}

type SizeStat struct {
	RepoSize   uint64 `json:"RepoSize"`
	StorageMax uint64 `json:"StorageMax"`
}

type FilesStat struct {
	Blocks         int    `json:"Blocks"`
	CumulativeSize uint64 `json:"CumulativeSize"`
	Hash           string `json:"Hash"`
	Local          bool   `json:"Local,omitempty"`
	Size           uint64 `json:"Size"`
	SizeLocal      uint64 `json:"SizeLocal,omitempty"`
	Type           string `json:"Type"`
	WithLocality   bool   `json:"WithLocality,omitempty"`
}

type StatsBitswap struct {
	BlocksReceived   uint64   `json:"BlocksReceived"`
	BlocksSent       uint64   `json:"BlocksSent"`
	DataReceived     uint64   `json:"DataReceived"`
	DataSent         uint64   `json:"DataSent"`
	DupBlksReceived  uint64   `json:"DupBlksReceived"`
	DupDataReceived  uint64   `json:"DupDataReceived"`
	MessagesReceived uint64   `json:"MessagesReceived"`
	Peers            []string `json:"Peers"`
	ProvideBufLen    int      `json:"ProvideBufLen"`
	Wantlist         []string `json:"Wantlist"`
}

type PeerStats struct {
	Exchanged uint64  `json:"Exchanged"`
	Peer      string  `json:"Peer"`
	Recv      uint64  `json:"Recv"`
	Sent      uint64  `json:"Sent"`
	Value     float64 `json:"Value"`
}

// Mock server implementation
func main() {
	http.HandleFunc("/api/v0/pin/ls", func(w http.ResponseWriter, r *http.Request) {
		resp := PinListResp{}
		resp.PinLsList.Keys = map[string]pinListKeysType{"QmcwQBzZcFVa7gyEQazd9WryzXKVMK2TvwBweruBZhy3pf": {Type: "direct"}}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/stats/repo", func(w http.ResponseWriter, r *http.Request) {
		resp := RepoInfo{
			NumObjects: 42,
			RepoPath:   "/mock/path",
			SizeStat: SizeStat{
				RepoSize:   123456789,
				StorageMax: 987654321,
			},
			Version:  "1.0.0",
			RepoSize: 123456789,
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/files/stat", func(w http.ResponseWriter, r *http.Request) {
		resp := FilesStat{
			Blocks:         3,
			CumulativeSize: 654321,
			Hash:           "QmcwQBzZcFVa7gyEQazd9WryzXKVMK2TvwBweruBZhy3pf",
			Local:          true,
			Size:           12345,
			Type:           "directory",
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/stats/bitswap", func(w http.ResponseWriter, r *http.Request) {
		resp := StatsBitswap{
			BlocksReceived:   10,
			BlocksSent:       5,
			DataReceived:     2048,
			DataSent:         1024,
			DupBlksReceived:  2,
			DupDataReceived:  512,
			MessagesReceived: 15,
			Peers:            []string{"peer1", "peer2"},
			ProvideBufLen:    0,
			Wantlist:         []string{"item1", "item2"},
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/bitswap/ledger", func(w http.ResponseWriter, r *http.Request) {
		resp := PeerStats{
			Exchanged: 0,
			Peer:      "mockPeerID",
			Recv:      0,
			Sent:      0,
			Value:     0,
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/block/stat", func(w http.ResponseWriter, r *http.Request) {
		resp := struct {
			Key  string `json:"Key"`
			Size int    `json:"Size"`
		}{
			Key:  "exampleKey",
			Size: 256,
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/id", func(w http.ResponseWriter, r *http.Request) {
		resp := struct {
			Addresses       []string `json:"Addresses"`
			AgentVersion    string   `json:"AgentVersion"`
			ID              string   `json:"ID"`
			ProtocolVersion string   `json:"ProtocolVersion"`
			Protocols       []string `json:"Protocols"`
			PublicKey       string   `json:"PublicKey"`
		}{
			Addresses:       []string{"mockAddress1", "mockAddress2"},
			AgentVersion:    "mockAgentVersion",
			ID:              "mockID",
			ProtocolVersion: "mockProtocolVersion",
			Protocols:       []string{"mockProtocol1", "mockProtocol2"},
			PublicKey:       "mockPublicKey",
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/log/level", func(w http.ResponseWriter, r *http.Request) {
		resp := struct {
			Message string `json:"Message"`
		}{
			Message: "Log level set",
		}
		json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/api/v0/stats/bw", func(w http.ResponseWriter, r *http.Request) {
		resp := struct {
			TotalIn  int64   `json:"TotalIn"`
			TotalOut int64   `json:"TotalOut"`
			RateIn   float64 `json:"RateIn"`
			RateOut  float64 `json:"RateOut"`
		}{
			TotalIn:  1024,
			TotalOut: 2048,
			RateIn:   1.5,
			RateOut:  2.5,
		}
		json.NewEncoder(w).Encode(resp)
	})

	// Default handler for unmatched routes
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	})

	// Start server
	log.Println("Mock IPFS server running on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
