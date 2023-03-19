#!/bin/bash

release=$(curl -sL 'https://api.github.com/repos/cumulusmx/CumulusMX/releases/latest' 2>/dev/null)

release_version=$(echo $release | jq .tag_name -r)

if [ -z "$release_version" ] || [ "$release_version" != "" ] || [ "$release_version" != "null" ]
  then
    echo "$release_version" > upstream-releases/cumulusmx-latest.txt
    echo "Latest version: $release_version"
fi
