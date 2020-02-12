# java-summon-docker-demo
CyberArk Summon Demo for Java app on Docker

# Insecure App

## Go to the tutorial folder
`cd tutorial`

## Start the insecure app & database
`docker-compose -f insecure-app.docker-compose.yml up -d`

## Test the insecure app

```
export insecure_app_url=http://localhost:8081
apt install -y wamerican
```

To list all pet messages:

`curl $insecure_app_url/pets`

To add a new message with a random name

`curl  -d "{\"name\": \"$(shuf -n 1 /usr/share/dict/american-english)\"}" -H "Content-Type: application/json" $insecure_app_url/pet`

You can repeat the above actions to create & review multiple entries.

## The Risk


Now, let us "think like an hacker" and review the files

Can you find the service account's embedded secrets?

Try the following command:

`grep DB_PASSWORD insecure-*`

Cool! You have found the service accounts.   Apparently it is far from ideal and definately not secure.

Let's clean up the environment before proceed
```
docker-compose -f insecure-app.docker-compose.yml down
echo y | docker volume prune
```

# Secure App

## Setup Conjur


We will summarize and fine tune the first step of the [offical Conjur tutorial](https://www.conjur.org/get-started/quick-start/oss-environment/) to set up a Conjur OSS environment.  If you want to know more it, please go to https://www.conjur.org/get-started/quick-start/oss-environment/


# Prepare the Setup script

<pre class="file" data-filename="setupConjur.sh" data-target="replace">#!/bin/bash
curl -o docker-compose.yml https://quincycheng.github.io/docker-compose.quickstart.yml
docker-compose pull
docker-compose run --no-deps --rm conjur data-key generate > data_key
export CONJUR_DATA_KEY="$(< data_key)"

docker-compose up -d 
echo "wait for 30 sec"
sleep 30s
docker-compose exec conjur conjurctl account create demo | tee admin.out
sleep 2s
api_key="$(grep API admin.out | cut -d: -f2 | tr -d ' \r\n')"
conjur_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tutorial_conjur_1 )"

docker-compose exec client bash -c "echo yes | conjur init -u $1 -a demo"
docker-compose exec client conjur authn login -u admin -p "$api_key"

export CONJUR_APPLIANCE_URL=http://$conjur_ip
export CONJUR_ACCOUNT="demo"
export CONJUR_AUTHN_LOGIN="admin"
export CONJUR_AUTHN_API_KEY="$api_key"
</pre>

```
chmod +x setupConjur.sh
```


Let's pull and setup a Conjur OSS. It will take a couple of moments 
```
./setupConjur.sh http://localhost:8080
```

## Policy


Now let's enroll the app to Conjur.   We refer to the [Enroll Application](https://www.conjur.org/get-started/tutorials/enrolling-application/) tutorial on conjur.org.   For details, please visit https://www.conjur.org/get-started/tutorials/enrolling-application/

# Prepare the policy files

1. Setup
We will model a simple application in which a frontend service connects to a db server. The db policy defines service account and its password, which the frontend application uses to log in to the database.

Here is a skeleton policy for this scenario, which simply defines two empty policies: db and frontend. Save this policy as “conjur.yml”:
<pre class="file" data-filename="conjur.yml" data-target="replace">- !policy
  id: db

- !policy
  id: frontend
</pre>

Then load it using the following command:
```
docker cp conjur.yml tutorial_client_1:/tmp/
docker-compose exec client conjur policy load --replace root /tmp/conjur.yml
```{{execute}}


2. Define Protected Resources
Having defined the policy framework, we can load the specific data for the database.

Create the following file as “db.yml”:

<pre class="file" data-filename="db.yml" data-target="replace"># Declare the secrets which are used to access the database
- &variables
  - !variable username
  - !variable password

# Define a group which will be able to fetch the secrets
- !group secrets-users

- !permit
  resource: *variables
  # "read" privilege allows the client to read metadata.
  # "execute" privilege allows the client to read the secret data.
  # These are normally granted together, but they are distinct
  #   just like read and execute bits on a filesystem.
  privileges: [ read, execute ]
  roles: !group secrets-users
</pre>

Now load it using the following command:

```
docker cp db.yml tutorial_client_1:/tmp/
docker-compose exec client conjur policy load db /tmp/db.yml
```{{execute}}

And store the secrets to Conjur
Username: `docker-compose exec client conjur variable values add db/username demo_service_account`{{execute}}

Password: `docker-compose exec client conjur variable values add db/password YourStrongSAPassword`{{execute}}

Please note that the password should be rotated regularly.   CyberArk CPM can help to archieve this.  For the list of supported devices, please refer to https://marketplace.cyberark.com

# Define an Application
For this example, the “frontend” policy will simply define a Layer and a Host. Create the following file as “frontend.yml”:
<pre class="file" data-filename="frontend.yml" data-target="replace">- !layer

- !host frontend-01

- !grant
  role: !layer
  member: !host frontend-01
</pre>
  
Note Statically defining the hosts in a policy is appropriate for fairly static infrastructure. More dynamic systems such as auto-scaling groups and containerized deployments can be managed with Conjur as well. The details of these topics are covered elsewhere.
Now load the frontend policy using the following command:

```
docker cp frontend.yml tutorial_client_1:/tmp/
docker-compose exec client conjur policy load frontend /tmp/frontend.yml|tee frontend.out
```


Note The `api_key` printed above is a unique securely random string for each host. When you load the policy, you’ll see a different API key. Be sure and use this API key below.  In this tutorial, we will save the output in `frontend.out` and the api key as environment variable `frontend_api`.   Please make sure they are removed from your production environment.

To get the frontend api key:
```
export frontend_api=$(tail -n +2 frontend.out | jq -r '.created_roles."demo:host:frontend/frontend-01".api_key')
```

# Entitlement

Now let's grant the access by updating the `db.yml` policy:
<pre class="file" data-filename="db.yml" data-target="replace">- &variables
  - !variable password

- !group secrets-users

- !permit
  resource: *variables
  privileges: [ read, execute ]
  roles: !group secrets-users

# Entitlements

- !grant
  role: !group secrets-users
  member: !layer /frontend
</pre>

Then load it using the CLI:
```
docker cp db.yml tutorial_client_1:/tmp/
docker-compose exec client conjur policy load db /tmp/db.yml
```


## Setup the Secure App
```
docker-compose -f docker-compose.yml -f secure-app.docker-compose.yml stop client
docker-compose -f docker-compose.yml -f secure-app.docker-compose.yml rm client
docker image rm cyberark/demo-app conjurinc/cli5 
docker-compose -f docker-compose.yml -f secure-app.docker-compose.yml up app db
```





