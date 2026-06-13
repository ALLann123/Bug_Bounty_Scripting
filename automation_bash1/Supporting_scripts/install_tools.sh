#!/usr/bin/env bash
# Install Go first if you haven't
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install the core toolkit
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
go install -v github.com/tomnomnom/assetfinder@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/tomnomnom/anew@latest
go install -v github.com/tomnomnom/gf@latest
go install -v github.com/tomnomnom/qsreplace@latest
go install -v github.com/hahwul/dalfox/v2@latest
go install -v github.com/haccer/subjack@latest

# Install GF(advanced grep tool) + gf patterns
go install github.com/tomnomnom/gf@latest
sudo cp ~/go/bin/gf /usr/local/bin/
 # GF Patterns
mkdir -p ~/.gf
git clone https://github.com/1ndianl33t/Gf-Patterns.git
cp Gf-Patterns/*.json ~/.gf

# install hakrawler
go install github.com/hakluke/hakrawler@latest
export PATH=$PATH:~/go/bin

# unfurl for filtering
go install github.com/tomnomnom/unfurl@latest
export PATH=$PATH:~/go/bin

# Install URO---> Python tool used to reclutter URL list for web crawling and security testing. Third party managed use pipx
apt update
apt install pipx -y

pipx ensurepath

pipx install uro

#verify install
uro --help
