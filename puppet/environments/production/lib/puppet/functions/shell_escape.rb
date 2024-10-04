require 'shellwords'

# Escapes a string for use as a shell argument.
Puppet::Functions.create_function(:shell_escape) do
    dispatch :impl do
        param 'String', :argument
        return_type 'String'
    end

    def impl(argument)
        argument.shellescape
    end
  end