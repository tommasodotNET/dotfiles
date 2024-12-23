echo "Installing dotnet"

{ #try 
sudo apt-get update && \
  sudo apt-get install -y dotnet-sdk-9.0
  echo "dotnet installed"
  
  echo "Trusting dotnet dev certs"
  dotnet dev-certs https --trust
} || { #catch
  echo "dotnet install failed"
}
