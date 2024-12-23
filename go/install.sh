if [[ which go ]]; then
    rm -rf /usr/local/go
fi
{ #try
    echo "Installing go"
    wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
    rm go1.23.4.linux-amd64.tar.gz
} || { #catch
    echo "go install failed"
}