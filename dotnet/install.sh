echo "Installing dotnet"

{ #try 
  curl -sSL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.100/dotnet-sdk-10.0.100-linux-x64.tar.gz -o dotnet-sdk-10.0.100-linux-x64.tar.gz
  mkdir -p $HOME/dotnet && tar zxf dotnet-sdk-10.0.100-linux-x64.tar.gz -C $HOME/dotnet
  export DOTNET_ROOT=$HOME/dotnet
  export PATH=$PATH:$HOME/dotnet

  echo "Trusting dotnet dev certs"
  dotnet dev-certs https --trust
} || { #catch
  echo "dotnet install failed"
}
