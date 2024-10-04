# Returns the directory part of the supplied filename.
Puppet::Functions.create_function(:dirname) do
    dispatch :impl do
        required_param 'String', :filename
        return_type 'String'
    end

    def impl(filename)
        File.dirname(filename)
    end
end