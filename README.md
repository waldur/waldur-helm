## Waldur helm

### Content

TODO

### Howto

Right now i use http repo not git for testing http://185.174.162.103/charts/waldur/

To create package from rancher you need to execute next steps

helm package waldur
mv nginx-0.1.0.tgz waldur
helm repo index waldur --url http://185.174.162.103/charts/waldur/

To generate new version

helm package nginx --version 1.1.1
