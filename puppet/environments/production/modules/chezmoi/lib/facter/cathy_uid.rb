# Determines the UID of the user who invoked `sudo puppet apply`, which is
# expected to be the UID of Cathy's user account.
Facter.add('cathy_uid') do
    def get_process_info(pid)
        raise 'get_process_info: pid must be an integer' unless pid.is_a? Integer

        uid, ppid = `ps -p '#{pid}' -o uid=,ppid=`.split
        return nil unless $?.success?

        # The following line will intentionally raise an error unless both
        # values are convertible to integers, as they should be.
        return Integer(uid), Integer(ppid)
    end

    setcode do
        cathy_uid = -> {
            unless Process.uid == 0
                return Process.uid if ENV['SUDO_UID'].to_i == Process.uid
                return -1
            end
            uid, ppid = get_process_info(Process.pid)
            my_uid = uid
            until ppid.nil?
                uid, ppid = get_process_info(ppid)
                if uid != my_uid
                    # The UID that we find should match the value of SUDO_UID.
                    return uid if ENV['SUDO_UID'].to_i == uid
                    break
                end
            end
            return -1
        }.call
        raise 'failed to determine cathy_uid' if cathy_uid == -1
        cathy_uid
    end
end