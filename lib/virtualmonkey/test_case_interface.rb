module VirtualMonkey
  module TestCaseInterface
    def set_var(sym, *args)
      behavior(sym, *args)
    end

    def behavior(sym, *args, &block)
      begin
        rerun_test
        #pre-command
        populate_settings unless @populated
        #command
        result = __send__(sym, *args)
        if block
          raise "FATAL: Failed behavior verification. Result was:\n#{result.inspect}" if not yield(result)
        end
        #post-command
        continue_test
      rescue Exception => e
        if block and e.message !~ /^FATAL: Failed behavior verification/
          dev_mode?(e) if not yield(e)
        else
          dev_mode?(e)
        end
      end while @rerun_last_command.pop
      result
    end

    def verify(method, expectation, *args)
      puts "TestCaseInterface::verify is deprecated!"
      if expectation =~ /((exception)|(error)|(fatal)|(fail))/i
        expect = "fail"
        error_msg = expectation.split(":")[1..-1].join(":")
      elsif expectation =~ /((success)|(succeed)|(pass))/i
        expect = "pass"
      elsif expectation =~ /nil/i
        expect = "nil"
      else
        raise 'Syntax Error: verify expects a "pass", "fail", or "nil"'
      end

      begin
        rerun_test
        result = __send__(method, *args)
        if expect != "pass" and not (result == nil and expect == "nil")
          raise "FATAL: Failed verification"
        end
        continue_test
      rescue Exception => e
        if not ("#{e}" =~ /#{error_msg}/ and expect == "fail")
          dev_mode?(e)
        end
      end while @rerun_last_command.pop
    end

    def probe(set, command, &block)
      # run command on set over ssh
      result = ""
      select_set(set).each { |s|
        begin
          rerun_test
          result_temp = s.spot_check_command(command)
          if not yield(result_temp[:output])
            raise "FATAL: Server #{s.nickname} failed probe. Got #{result_temp[:output]}"
          end
          continue_test
        rescue Exception => e
          dev_mode?(e)
        end while @rerun_last_command.pop
        result += result_temp[:output]
      }
    end

    private

    def dev_mode?(e)
      if not ENV['MONKEY_NO_DEBUG'] =~ /true/i
        puts "Got exception: #{e.message}"
        puts "Backtrace: #{e.backtrace.join("\n")}"
        puts "Pausing for debugging..."
        debugger
      else
        exception_handle(e)
      end
    end

    def exception_handle(e)
      puts "ATTENTION: Using default exception_handle(e). This can be overridden in mixin classes."
      if e.message =~ /Insufficient capacity/
        puts "Got \"Insufficient capacity\". Retrying...."
        sleep 60
      elsif e.message =~ /Service Temporarily Unavailable/
        puts "Got \"Service Temporarily Unavailable\". Retrying...."
        sleep 10
      else
        raise e
      end
    end

    def help
      puts "Here are some of the wrapper methods that may be of use to you in your debugging quest:\n"
      puts "behavior(sym, *args, &block): Pass the method name (as a symbol or string) and the optional arguments"
      puts "                              that you wish to pass to that method; behavior() will call that method"
      puts "                              with those arguments while handling nested exceptions, retries, and"
      puts "                              debugger calls. If a block is passed, it should take one argument, the"
      puts "                              return value of the function 'sym'. The block should always check"
      puts "                              if the return value is an Exception or not, and validate accordingly.\n"
      puts "                              Examples:"
      puts "                                behavior(:launch_all)"
      puts "                                behavior(:launch_set, 'Load Balancer')"
      puts "                                behavior(:run_script_on_all, 'fail') { |r| r.is_a?(Exception) }\n"
      puts "probe(server_set, shell_command, &block): Provides a one-line interface for running a command on"
      puts "                                          a set of servers and verifying their output. The block"
      puts "                                          should take one argument, the output string from one of"
      puts "                                          the servers, and return true or false based on however"
      puts "                                          the developer wants to verify correctness.\n"
      puts "                                          Examples:"
      puts "                                            probe('.*', 'ls') { |s| puts s }"
      puts "                                            probe(:fe_servers, 'ls') { |s| puts s }"
      puts "                                            probe('app_servers', 'ls') { |s| puts s }"
      puts "                                            probe('.*', 'uname -a') { |s| s =~ /x64/ }\n"
      puts "continue_test: Disables the retry loop that reruns the last command (the current command that you're"
      puts "               debugging.\n"
      puts "help: Prints this help message."
    end

    def populate_settings
      @servers.each { |s| s.settings }
      lookup_scripts
      @populated = 1
    end

    def select_set(set = @servers)
      if set.is_a?(String)
        if self.respond_to?(set.to_sym)
          set = set.to_sym
        else
          set = @servers.select { |s| s.nickname =~ /#{set}/ }
        end
      end
      set = behavior(set) if set.is_a?(Symbol)
      set = [ set ] unless set.is_a?(Array)
      return set
    end

    def object_behavior(obj, sym, *args, &block)
      begin
        rerun_test
        #pre-command
        populate_settings unless @populated
        #command
        result = obj.__send__(sym, *args)
        #post-command
        continue_test
      rescue Exception => e
        dev_mode?(e)
      end while @rerun_last_command.pop
      result
    end

    def rerun_test
      @rerun_last_command.push(true)
    end

    def continue_test
      @rerun_last_command.pop
      @rerun_last_command.push(false)
    end
  end
end
