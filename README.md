# NetAuth
NetAuth is a single docker image that implements a lightweight identity and access manager with tools already established in the industry. NetAuth aims to provide network authentication mechanisms simply and quickly deployable on Foundxtion deployed machines. 

# Used in NetAuth
- An OpenLDAP server used for managing identity of an organization which uses Foundxtion.
- A KerberosV5 setup with kdc and kadmin servers used for handling authentication mechanisms.
- A SASLAuthd gateway used by OpenLDAP server to contact the kdc service when user is attempting to identify itself through OpenLDAP. 
