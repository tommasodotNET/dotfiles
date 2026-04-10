echo "Installing dotnet"

{ #try 
  curl -sSL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.201/dotnet-sdk-10.0.201-linux-x64.tar.gz -o dotnet-sdk-10.0.201-linux-x64.tar.gz
  mkdir -p $HOME/dotnet && tar zxf dotnet-sdk-10.0.201-linux-x64.tar.gz -C $HOME/dotnet
  export DOTNET_ROOT=$HOME/dotnet
  export PATH=$PATH:$HOME/dotnet

  echo "Trusting dotnet dev certs"
  dotnet dev-certs https --trust

  export SSL_CERT_DIR="$HOME/.aspnet/dev-certs/trust:/usr/lib/ssl/certs"
} || { #catch
  echo "dotnet install failed"
}
