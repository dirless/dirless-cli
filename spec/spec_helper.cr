require "spec"
require "webmock"
require "age-crystal"
require "../src/config"
require "../src/hmac_key"
require "../src/providers/aws"

# Reset all HTTP stubs before each spec so they don't bleed across tests
Spec.before_each { WebMock.reset }
