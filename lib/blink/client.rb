#!/usr/local/bin/ruby -w

# $Id$

# the available clients

require 'blink'
require 'blink/function'
require 'blink/type'
require 'blink/fact'
require 'blink/transaction'
require 'blink/transportable'
require 'http-access2'
require 'soap/rpc/driver'
require 'soap/rpc/httpserver'
#require 'webrick/https'
require 'logger'

module Blink
    class ClientError < RuntimeError; end
    #---------------------------------------------------------------
    class Client < SOAP::RPC::HTTPServer
        def initialize(hash)
            # to whom do we connect?
            @server = nil
            @nil = nil
            @url = hash[:Server]
            if hash.include?(:Listen) and hash[:Listen] == false
                Blink.notice "We're a local client"
                @localonly = true
                @driver = @url
            else
                Blink.notice "We're a networked client"
                @localonly = false
                @driver = SOAP::RPC::Driver.new(@url, 'urn:blink-server')
                @driver.add_method("getconfig", "name")
            end
            unless @localonly
                hash.delete(:Server)

                Blink.notice "Server is %s" % @url

                hash[:BindAddress] ||= "0.0.0.0"
                hash[:Port] ||= 17444
                hash[:Debug] ||= true
                hash[:AccessLog] ||= []

                super(hash)
            end
        end

        def getconfig
            Blink.debug "server is %s" % @url
            #client.loadproperty('files/sslclient.properties')
            Blink.notice("getting config")
            objects = nil
            if @localonly
                objects = @driver.getconfig(self)
            else
                objects = @driver.getconfig(Blink::Fact["hostname"])
            end
            self.config(objects)
        end

        # this method is how the client receives the tree of Transportable
        # objects
        # for now, just descend into the tree and perform and necessary
        # manipulations
        def config(tree)
            Blink.notice("Calling config")
            container = Marshal::load(tree).to_type

            # for now we just evaluate the top-level container, but eventually
            # there will be schedules and such associated with each object,
            # and probably with the container itself
            transaction = container.evaluate
            #transaction = Blink::Transaction.new(objects)
            transaction.evaluate
            self.shutdown
        end

        def callfunc(name,args)
            Blink.notice("Calling callfunc on %s" % name)
            if function = Blink::Function[name]
                #Blink.debug("calling function %s" % function)
                value = function.call(args)
                #Blink.debug("from %s got %s" % [name,value])
                return value
            else
                raise "Function '%s' not found" % name
            end
        end

        private

        def on_init
            @default_namespace = 'urn:blink-client'
            add_method(self, 'config', 'config')
            add_method(self, 'callfunc', 'name', 'arguments')
        end

        def cert(filename)
            OpenSSL::X509::Certificate.new(File.open(File.join(@dir, filename)) { |f|
                f.read
            })
        end

        def key(filename)
            OpenSSL::PKey::RSA.new(File.open(File.join(@dir, filename)) { |f|
                f.read
            })
        end

    end
    #---------------------------------------------------------------
end
