package main

import (
	"bufio"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"github.com/sunliang711/goutils/config"
)

func main() {
	err := config.InitConfigLogger()
	if err != nil {
		logrus.Fatalf("init confg logger error: %s", err.Error())
	}
	portFile := viper.GetString("portFile")
	if portFile == "" {
		logrus.Fatalf("Need portFile in config file")
	}
	rd, err := os.Open(portFile)
	if err != nil {
		logrus.Fatalf("Open port file error: %v", err)
	}
	var pps []*PortPs
	scan := bufio.NewScanner(rd)
	for scan.Scan() {
		line := scan.Text()
		parts := strings.Split(line, ":")
		if len(parts) == 2 {
			port, err := strconv.Atoi(parts[0])
			if err != nil {
				logrus.Errorf("parse port error: %v", err)
				continue
			}
			pps = append(pps, &PortPs{port, parts[1]})
		}
	}

	// logrus.SetLevel(logrus.DebugLevel)
	// pps := []*PortPs{
	// 	&PortPs{18000, "新加坡01"},
	// 	&PortPs{18001, "台湾01"},
	// 	&PortPs{18002, "日本01"},
	// 	&PortPs{18003, "新加坡02"},
	// }

	fastestPort(pps, viper.GetInt("timeout"), viper.GetString("targetURL"), viper.GetString("resultFile"), viper.GetInt("maxCocurrent"))
}

type PortPs struct {
	Port int
	Ps   string
}

func fastestPort(pps []*PortPs, timeout int, targetURL string, outputFile string, maxCocurrent int) error {
	file, err := os.OpenFile(outputFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0666)
	if err != nil {
		return err
	}
	defer file.Close()
	logrus.Infof("result file: %v", outputFile)
	logrus.Infof("maxCocurrent: %v", maxCocurrent)

	cocurrentChan := make(chan struct{}, maxCocurrent)

	var wg sync.WaitGroup

	for _, pp := range pps {
		cocurrentChan <- struct{}{}
		wg.Add(1)
		go func(pp *PortPs) {
			defer func() {
				<-cocurrentChan
			}()
			defer wg.Done()
			parsedProxy, err := url.Parse(fmt.Sprintf("socks5://localhost:%d", pp.Port))
			if err != nil {
				logrus.Errorf("parse proxy url for port: %v ps: %v error: %v", pp.Port, pp.Ps, err)
				return
			}
			logrus.Debugf("parsedProxy: %v", parsedProxy)
			client := &http.Client{
				Transport: &http.Transport{Proxy: http.ProxyURL(parsedProxy)},
				Timeout:   time.Millisecond * time.Duration(timeout),
			}
			start := time.Now()
			_, err = client.Get(targetURL)
			if err != nil {
				logrus.Errorf("port: %v ps: %v Error: %v", pp.Port, pp.Ps, err)
				return
			}
			elapsedMS := time.Since(start).Milliseconds()

			logrus.Infof("port: %v elapsed time: %v [ms] ps: %v", pp.Port, elapsedMS, pp.Ps)
			_, err = file.WriteString(fmt.Sprintf("%v`%v`%v\n", pp.Port, elapsedMS, pp.Ps))
			if err != nil {
				logrus.Errorf("Write elapsedMS to file: %v error: %v", outputFile, err)
			}
		}(pp)
	}
	wg.Wait()
	return nil
}
