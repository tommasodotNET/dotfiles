echo "Installing dotnet"

{ #try 
  curl https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.100-preview.7.25380.108/dotnet-sdk-10.0.100-preview.7.25380.108-linux-x64.tar.gz
  tar zxf dotnet-sdk-10.0.100-preview.7.25380.108-linux-x64.tar.gz -C /usr/local/share/dotnet
  
  echo "Trusting dotnet dev certs"
  dotnet dev-certs https --trust
} || { #catch
  echo "dotnet install failed"
}
