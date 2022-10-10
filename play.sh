echo "/c/Users/nlrdn/GravitySource/rluisn-devtest/versioning/.git/hooks" | awk '{ gsub(/.git/, ""); print }' | awk '{ gsub(/hooks/, ""); print }' | sed 's/.$//' | sed 's/.$//'
awk '{gsub(/[^[:alnum:]^[:blank:]]*/,x); print}'
