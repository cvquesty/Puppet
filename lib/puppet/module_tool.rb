# encoding: UTF-8
# Load standard libraries
require 'pathname'
require 'fileutils'
require 'puppet/util/colors'

module Puppet
  module ModuleTool
    require 'puppet/module_tool/tar'
    extend Puppet::Util::Colors

    # Directory and names that should not be checksummed.
    ARTIFACTS = ['pkg', /^\./, /^~/, /^#/, 'coverage', 'metadata.json', 'REVISION']
    FULL_MODULE_NAME_PATTERN = /\A([^-\/|.]+)[-|\/](.+)\z/
    REPOSITORY_URL = Puppet.settings[:module_repository]

    # Is this a directory that shouldn't be checksummed?
    #
    # TODO: Should this be part of Checksums?
    # TODO: Rename this method to reflect its purpose?
    # TODO: Shouldn't this be used when building packages too?
    def self.artifact?(path)
      case File.basename(path)
      when *ARTIFACTS
        true
      else
        false
      end
    end

    # Return the +username+ and +modname+ for a given +full_module_name+, or raise an
    # ArgumentError if the argument isn't parseable.
    def self.username_and_modname_from(full_module_name)
      if matcher = full_module_name.match(FULL_MODULE_NAME_PATTERN)
        return matcher.captures
      else
        raise ArgumentError, "Not a valid full name: #{full_module_name}"
      end
    end

    # Find the module root when given a path by checking each directory up from
    # its current location until it finds one that contains a file called
    # 'Modulefile'.
    #
    # @param path [Pathname, String] path to start from
    # @return [Pathname, nil] the root path of the module directory or nil if
    #   we cannot find one
    def self.find_module_root(path)
      path = Pathname.new(path) if path.class == String

      path.expand_path.ascend do |p|
        return p if is_module_root?(p)
      end

      nil
    end

    # Analyse path to see if it is a module root directory by detecting a
    # file named 'Modulefile' in the directory.
    #
    # @param path [Pathname, String] path to analyse
    # @return [Boolean] true if the path is a module root, false otherwise
    def self.is_module_root?(path)
      path = Pathname.new(path) if path.class == String

      FileTest.file?(path + 'Modulefile')
    end

    # Builds a formatted tree from a list of node hashes containing +:text+
    # and +:dependencies+ keys.
    def self.format_tree(nodes, level = 0)
      str = ''
      nodes.each_with_index do |node, i|
        last_node = nodes.length - 1 == i
        deps = node[:dependencies] || []

        str << (indent = "  " * level)
        str << (last_node ? "└" : "├")
        str << "─"
        str << (deps.empty? ? "─" : "┬")
        str << " #{node[:text]}\n"

        branch = format_tree(deps, level + 1)
        branch.gsub!(/^#{indent} /, indent + '│') unless last_node
        str << branch
      end

      return str
    end

    def self.build_tree(mods, dir)
      mods.each do |mod|
        version_string = mod[:version].to_s.sub(/^(?!v)/, 'v')

        if mod[:action] == :upgrade
          previous_version = mod[:previous_version].to_s.sub(/^(?!v)/, 'v')
          version_string = "#{previous_version} -> #{version_string}"
        end

        mod[:text] = "#{mod[:name]} (#{colorize(:cyan, version_string)})"
        mod[:text] += " [#{mod[:path]}]" unless mod[:path].to_s == dir.to_s

        deps = (mod[:dependencies] || [])
        deps.sort! { |a, b| a[:name] <=> b[:name] }
        build_tree(deps, dir)
      end
    end

    # @param options [Hash<Symbol,String>] This hash will contain any
    #   command-line arguments that are not Settings, as those will have already
    #   been extracted by the underlying application code.
    #
    # @note Unfortunately the whole point of this method is the side effect of
    # modifying the options parameter.  This same hash is referenced both
    # when_invoked and when_rendering.  For this reason, we are not returning
    # a duplicate.
    # @todo Validate the above note...
    #
    # An :environment_instance and a :target_dir are added/updated in the
    # options parameter.
    #
    # @api private
    def self.set_option_defaults(options)
      current_environment = environment_from_options(options)

      modulepath = [options[:target_dir]] + current_environment.full_modulepath

      face_environment = current_environment.override_with(:modulepath => modulepath.compact)

      options[:environment_instance] = face_environment

      # Note: environment will have expanded the path
      options[:target_dir] = face_environment.full_modulepath.first
    end

    # Given a hash of options, we should discover or create a
    # {Puppet::Node::Environment} instance that reflects the provided options.
    #
    # Generally speaking, the `:modulepath` parameter should supercede all
    # others, the `:environment` parameter should follow after that, and we
    # should default to Puppet's current environment.
    #
    # @param options [{Symbol => Object}] the options to derive environment from
    # @return [Puppet::Node::Environment] the environment described by the options
    def self.environment_from_options(options)
      if options[:modulepath]
        path = options[:modulepath].split(File::PATH_SEPARATOR)
        Puppet::Node::Environment.create(:anonymous, path, '')
      elsif options[:environment].is_a?(Puppet::Node::Environment)
        options[:environment]
      elsif options[:environment]
        Puppet.lookup(:environments).get(options[:environment])
      else
        Puppet.lookup(:current_environment)
      end
    end
  end
end

# Load remaining libraries
require 'puppet/module_tool/errors'
require 'puppet/module_tool/applications'
require 'puppet/module_tool/checksums'
require 'puppet/module_tool/contents_description'
require 'puppet/module_tool/dependency'
require 'puppet/module_tool/metadata'
require 'puppet/module_tool/modulefile'
require 'puppet/module_tool/skeleton'
require 'puppet/forge/cache'
require 'puppet/forge'
