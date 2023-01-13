import datetime
import saml2

# wiki: http://docs.waldur.com/Identityproviders
WALDUR_AUTH_SAML2.update({
    # used for assigning the registration method to the user
    'NAME': 'saml2',
    # full path to the xmlsec1 binary program
    'XMLSEC_BINARY': '/usr/bin/xmlsec1',
    # set to True to output debugging information
    'DEBUG': True,
    # IdPs metadata XML files stored locally
    'IDP_METADATA_LOCAL': [
        '/etc/waldur/saml2/metadata/edugain_metadata.xml',
    ],
    # IdPs metadata XML files stored remotely
    'IDP_METADATA_REMOTE':
    [
    ],
    # logging
    # empty to disable logging SAML2-related stuff to file
    'LOG_FILE': '',
    'LOG_LEVEL': 'DEBUG',
    # Indicates if the entity will sign the logout requests
    'LOGOUT_REQUESTS_SIGNED': 'true',
    # Indicates if the authentication requests sent should be signed by default
    'AUTHN_REQUESTS_SIGNED': 'true',
    # PEM formatted certificate chain file
    'CERT_FILE': '/etc/waldur/saml2/credentials/sp.crt',
    # PEM formatted certificate key file -- a private copy of the file inside docker image
    'KEY_FILE': '/etc/waldur/saml2/credentials/sp.pem',
    # SAML attributes that are required to identify a user
    'REQUIRED_ATTRIBUTES': [
        'cn',
        'givenName',
        'surname',
        'mail',
        'schacPersonalUniqueID',
        'eduPersonPrincipalName',
    ],
    # SAML attributes that may be useful to have but not required
    'OPTIONAL_ATTRIBUTES': [
        'schacHomeOrganization', 'preferredLanguage', 'eduPersonScopedAffiliation'
    ],
    # mapping between SAML attributes and User fields
    'SAML_ATTRIBUTE_MAPPING': {
        'eduPersonPrincipalName': ['username'],
        'schacPersonalUniqueID': ['civil_number'],
        'cn': ['full_name'],
        'givenName': ['first_name'],
        'surname': ['last_name'],
        'mail': ['email'],
        'preferredLanguage': ['preferred_language'],
        'schacHomeOrganization': ['organization'],
        'eduPersonScopedAffiliation': ['_process_saml2_affiliations'],
    },
    # organization responsible for the service
    # you can set multilanguage information here
    'ORGANIZATION': {
        'name': [('Example', 'et'), ('Example', 'en'), ('Example', 'lt')],
        'display_name': [('Example', 'et'), ('Example', 'en'), ('Example', 'lt'),],
        'url': [('https://waldur.example.com/', 'et'), ('https://waldur.example.com/', 'en'), ('https://waldur.example.com/', 'lt')],
    },

    # eduGAIN CoCo settings
    'PRIVACY_STATEMENT_URL': 'https://waldur.example.com/views/policy/privacy-full.html',
    'DISPLAY_NAME': 'Example Self-Service',
    'DESCRIPTION': 'Self-service for users of Example',

    # mdpi attributes
    'REGISTRATION_POLICY': 'http://reg.example.com/main/wp-content/uploads/Federation_Policy_1.3.pdf',
    'REGISTRATION_AUTHORITY': 'http://reg.example.com',
    'REGISTRATION_INSTANT': datetime.datetime(2017, 1, 1).isoformat(),
    'IDENTITY_PROVIDER_LABEL': 'WALDUR',
})

SAML_ATTRIBUTE_MAPPING = WALDUR_AUTH_SAML2['SAML_ATTRIBUTE_MAPPING']

SAML_CONFIG.update({
    'xmlsec_binary': WALDUR_AUTH_SAML2['XMLSEC_BINARY'],
    'entityid': WALDUR_CORE['MASTERMIND_URL'] + '/api-auth/saml2/metadata/',
    'attribute_map_dir': WALDUR_AUTH_SAML2['ATTRIBUTE_MAP_DIR'],
    'name': WALDUR_AUTH_SAML2['DISPLAY_NAME'],
    'extensions': {
        'mdrpi': {
            'RegistrationInfo': {
                'registration_policy': {
                    'lang': 'en',
                    'text': WALDUR_AUTH_SAML2['REGISTRATION_POLICY'],
                },
                'registrationAuthority': WALDUR_AUTH_SAML2['REGISTRATION_AUTHORITY'],
                'registrationInstant': WALDUR_AUTH_SAML2['REGISTRATION_INSTANT'],
            },
        },
    },
    'contact_person': [
        {
            'email_address': 'mailto:waldur@example.com',
            'contact_type': 'technical',
            'given_name': 'Administrator',
        },
    ],
    'service': {
        'sp': {
            # for compatibility with older IdPs. See also https://github.com/IdentityPython/pysaml2/issues/490
            'want_response_signed': False,
            'logout_requests_signed': WALDUR_AUTH_SAML2['LOGOUT_REQUESTS_SIGNED'],
            'authn_requests_signed': WALDUR_AUTH_SAML2['AUTHN_REQUESTS_SIGNED'],
            'endpoints': {
                'assertion_consumer_service': [
                    (WALDUR_CORE['MASTERMIND_URL'], '/api-auth/saml2/login/complete/',
                     saml2.BINDING_HTTP_POST),
                ],
                'single_logout_service': [
                    (WALDUR_CORE['MASTERMIND_URL'], '/api-auth/saml2/logout/complete/',
                     saml2.BINDING_HTTP_REDIRECT),
                    (WALDUR_CORE['MASTERMIND_URL'], '/api-auth/saml2/logout/complete/',
                     saml2.BINDING_HTTP_POST),
                ],
            },
            'allow_unsolicited': True,  # NOTE: This is the cornerstone! Never set to False
            'extensions': {
                'mdui': {
                    'UIInfo': {
                        'display_name': {
                            'lang': 'en',
                            'text': WALDUR_AUTH_SAML2['DISPLAY_NAME'],
                        },
                        'description': {
                            'lang': 'en',
                            'text': WALDUR_AUTH_SAML2['DESCRIPTION'],
                        },
                        'privacy_statement_url': {
                            'lang': 'en',
                            'text': WALDUR_AUTH_SAML2['PRIVACY_STATEMENT_URL'],
                        },
                        'logo': {
                            'text': 'https://waldur.example.com/login-logo.png',
                        },
                    },
                },
                'mdrpi': {
                    'RegistrationInfo': {
                        'registration_policy': {
                            'lang': 'en',
                            'text': WALDUR_AUTH_SAML2['REGISTRATION_POLICY'],
                        },
                        'registrationAuthority': WALDUR_AUTH_SAML2['REGISTRATION_AUTHORITY'],
                        'registrationInstant': WALDUR_AUTH_SAML2['REGISTRATION_INSTANT'],
                    },
                }
            },
            'required_attributes': WALDUR_AUTH_SAML2['REQUIRED_ATTRIBUTES'],
            'optional_attributes': WALDUR_AUTH_SAML2['OPTIONAL_ATTRIBUTES'],
        },
    },
    'metadata': [
        {
            'class': 'waldur_auth_saml2.utils.DatabaseMetadataLoader',
            'metadata': [('waldur_auth_saml2.utils.DatabaseMetadataLoader',)],
        },
    ],
    'organization': WALDUR_AUTH_SAML2['ORGANIZATION'],
    'debug': int(WALDUR_AUTH_SAML2['DEBUG']),
    'key_file': WALDUR_AUTH_SAML2['KEY_FILE'],
    'cert_file': WALDUR_AUTH_SAML2['CERT_FILE'],
    # keys are required in order to be able to decrypt encrypted messages from IdPs
    'encryption_keypairs': [{"key_file": WALDUR_AUTH_SAML2['KEY_FILE'], "cert_file": WALDUR_AUTH_SAML2['CERT_FILE']}],
})

if WALDUR_AUTH_SAML2['LOG_FILE'] != '':
    level = WALDUR_AUTH_SAML2['LOG_LEVEL'].upper()
    LOGGING['handlers']['file-saml2'] = {
        'class': 'logging.handlers.WatchedFileHandler',
        'filename': WALDUR_AUTH_SAML2['LOG_FILE'],
        'formatter': 'simple',
        'level': level,
    }

    LOGGING['loggers']['djangosaml2'] = {
        'handlers': ['file-saml2'],
        'propagate': True,
        'level': level,
    }

    LOGGING['loggers']['saml2'] = {
        'handlers': ['file-saml2'],
        'propagate': True,
        'level': level,
    }

SAML_CONFIG['encryption_keypairs'] = [{
    'key_file': WALDUR_AUTH_SAML2['KEY_FILE'],
    'cert_file': WALDUR_AUTH_SAML2['CERT_FILE'],
}]

for remote in WALDUR_AUTH_SAML2['IDP_METADATA_REMOTE']:
    SAML_CONFIG['metadata'].append({
        'class': 'saml2.mdstore.MetaDataExtern',
        'metadata': [(remote['url'], remote['cert'])]
    })
