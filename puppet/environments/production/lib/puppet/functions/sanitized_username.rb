# Returns a version of a username that is safe to incorporate into shell commands,
# even without any kind of quotation marks or escaping.
Puppet::Functions.create_function(:sanitized_username) do
    dispatch :impl do
        required_param 'String', :username
        return_type 'String'
    end

    def impl(username)
        result = username.gsub(/[^\w-]/, '')
        raise 'sanitized_username should return the original username' unless username == result
        result
    end
end