package CGI::Application::Plugin::LogDispatch;

use Log::Dispatch;
use Log::Dispatch::Screen;

use strict;
use vars qw($VERSION @EXPORT);

require Exporter;
require UNIVERSAL::require;

@EXPORT = qw(
  log
  log_config
);
sub import { goto &Exporter::import }

$VERSION = 0.01;

sub log {
    my $self = shift;

    if (!$self->{__LOG}) {
        # define the config hash if it doesn't exist to save some checks later
        $self->{__LOG_CONFIG} = {} unless $self->{__LOG_CONFIG};

        # create Log::Dispatch object
        $self->{__LOG} = Log::Dispatch->new( callbacks => sub { my %hash = @_; chomp $hash{message}; return $hash{message}.$/; } );

        if ($self->{__LOG_CONFIG}->{LOG_DISPATCH_OPTIONS}) {
            # use the parameters the user supplied
            $self->{__LOG} = Log::Dispatch->new( %{ $self->{__LOG_CONFIG}->{LOG_DISPATCH_OPTIONS} } );
        } else {
            $self->{__LOG} = Log::Dispatch->new( );
        }

        if ($self->{__LOG_CONFIG}->{LOG_DISPATCH_MODULES}) {
            foreach my $logger (@{ $self->{__LOG_CONFIG}->{LOG_DISPATCH_MODULES} }) {
                if (!$logger->{module}) {
                    # no logger module provided
                    #  not fatal... just skip this logger
                    warn "No 'module' name provided -- skipping this logger";
                } elsif (!$logger->{module}->require) {
                    # Couldn't load the logger module
                    #  not fatal... just skip this logger
                    warn $UNIVERSAL::require::ERROR;
                } else {
                    my $module = delete $logger->{module};
                    # setup a callback to append a newline if requested
                    if ($logger->{append_newline} || $self->{__LOG_CONFIG}->{APPEND_NEWLINE}) {
                        delete $logger->{append_newline} if exists $logger->{append_newline};
                        $logger->{callbacks} = [ $logger->{callbacks} ]
                            if $logger->{callbacks} &&  ref $logger->{callbacks} ne 'ARRAY';
                        push @{ $logger->{callbacks} }, \&append_newline;
                    }
                    # add the logger to the dispatcher
                    $self->{__LOG}->add( $module->new( %$logger ) );
                }
            }
        } else {
            # create a simple STDERR logger
            my %options = (
                                name => 'screen',
                              stderr => 1,
                           min_level => 'debug',
            );
            $options{callbacks} = \&append_newline if $self->{__LOG_CONFIG}->{APPEND_NEWLINE};
            $self->{__LOG}->add( Log::Dispatch::Screen->new( %options ) );
        }
    }

    return $self->{__LOG};
}

sub log_config {
    my $self = shift;

    if (@_) {
        die "Calling log_config after the log object has already been created" if (defined $self->{__LOG});
        my $props;
        if (ref($_[0]) eq 'HASH') {
            my $rthash = %{$_[0]};
            $props = $self->_cap_hash($_[0]);
        } else {
            $props = $self->_cap_hash({ @_ });
        }

        # Check for LOG_OPTIONS
        if ($props->{LOG_DISPATCH_OPTIONS}) {
            die "log_config error:  parameter LOG_DISPATCH_OPTIONS is not a hash reference"
                if ref $props->{LOG_DISPATCH_OPTIONS} ne 'HASH';
            $self->{__LOG_CONFIG}->{LOG_DISPATCH_OPTIONS} = delete $props->{LOG_DISPATCH_OPTIONS};
        }

        # Check for LOG_DISPATCH_MODULES
        if ($props->{LOG_DISPATCH_MODULES}) {
            die "log_config error:  parameter LOG_DISPATCH_MODULES is not an array reference"
                if ref $props->{LOG_DISPATCH_MODULES} ne 'ARRAY';
            $self->{__LOG_CONFIG}->{LOG_DISPATCH_MODULES} = delete $props->{LOG_DISPATCH_MODULES};
        }

        # Check for APPEND_NEWLINE
        if ($props->{APPEND_NEWLINE}) {
            $self->{__LOG_CONFIG}->{APPEND_NEWLINE} = 1;
            delete $props->{APPEND_NEWLINE};
        }

        # Check for LOG_METHOD_EXECUTION
        if ($props->{LOG_METHOD_EXECUTION}) {
            die "log_config error:  parameter LOG_METHOD_EXECUTION is not an array reference"
                if ref $props->{LOG_METHOD_EXECUTION} ne 'ARRAY';
            log_subroutine_calls($self->log, @{$props->{LOG_METHOD_EXECUTION}});
            delete $props->{LOG_METHOD_EXECUTION};
        }

        # If there are still entries left in $props then they are invalid
        die "Invalid option(s) (".join(', ', keys %$props).") passed to log_config" if %$props;
    }

    $self->{__LOG_CONFIG};
}

sub log_subroutine_calls {
  my $log = shift;
  eval {
    Sub::WrapPackages->require;
    Sub::WrapPackages->import(
                            packages => [@_],
                            pre      => sub {
                              $log->debug("calling $_[0](".join(', ', @_[1..$#_]).")");
                            },
                            post     => sub {
                              no warnings qw(uninitialized);
                              $log->debug("returning from $_[0] (".join(', ', @_[1..$#_]).")");
                            }
    );
    1;
  } or do {
    $log->error("Failed to load and configure Sub::WrapPackages:  $@");
  };
}

sub append_newline {
  my %hash = @_;
  chomp $hash{message};
  return $hash{message}.$/;
}


1;
__END__

=head1 NAME

CGI::Application::Plugin::LogDispatch - Add Log::Dispatch support to CGI::Application


=head1 SYNOPSIS

 use CGI::Application::Plugin::LogDispatch;

 $self->log->info('Information message');
 $self->log->debug('Debug message');

=head1 DESCRIPTION

CGI::Application::Plugin::LogDispatch adds logging support to your L<CGI::Application>
modules by providing a L<Log::Dispatch> dispatcher object that is accessible from
anywhere in the application.

=head1 METHODS

=head2 log

This method will return the current L<Log::Dispatch> dispatcher object.  The L<Log::Dispatch>
object is created on the first call to this method, and any subsequent calls will return the
same object.  This effectively creates a singleton log dispatcher for the duration of the request.
If C<log_config> has not been called before the first call to C<log>, then it will choose some
sane defaults to create the dispatcher object (the exact default values are defined below).

  # retrieve the log object
  my $log = $self->log;
  $log->warning("something's not right!";
  $log->emergency("It's all gone pear shaped!";
 
  - or -
 
  # use the log object directly
  $self->log->debug(Data::Dumper::Dumper(\%hash));


=head2 log_config

This method can be used to customize the functionality of the CGI::Application::Plugin::LogDispatch module.
Calling this method does not mean that a new L<Log::Dispatch> object will be immediately created.
The log object will not be created until the first call to $self->log.

The recommended place to call C<log_config> is in the C<cgiapp_init>
stage of L<CGI::Application>.  If this method is called after the log object
has already been accessed, then it will die with an error message.

If this method is not called at all then a reasonable set of defaults
will be used (the exact default values are defined below).

The following parameters are accepted:

=over 4

=item LOG_DISPATCH_OPTIONS

This allows you to customize how the L<Log::Dispatch> object is created by providing a hash of
options that will be passed to the L<Log::Dispatch> constructor.  Please see the documentation
for L<Log::Dispatch> for the exact syntax of the parameters.  Surprisingly enough you will usually
not need to use this option, instead look at the LOG_DISPATCH_MODULES option.

 LOG_DISPATCH_OPTIONS => {
      callbacks => sub { my %h = @_; return time().': '.$h{message}; },
 }

=item LOG_DISPATCH_MODULES

This option allows you to specify the Log::Dispatch::* modules that you wish to use to
log messages.  You can list multiple dispatch modules, each with their own set of options.  Format
the options in an array of hashes, where each hash contains the options for the Log::Dispatch::
module you are configuring and also include a 'module' parameter containing the name of the
dispatch module.  See below for an example.  You can also add an 'append_newline' option to
automatically append a newline to each log entry for this dispatch module (this option is
not needed if you already specified the APPEND_NEWLINE option listed below which will add
a newline for all dispatch modules).

 LOG_DISPATCH_MODULES => [ 
   {         module => 'Log::Dispatch::File',
               name => 'messages',
           filename => '/tmp/messages.log',
          min_level => 'info',
     append_newline => 1
   },
   {         module => 'Log::Dispatch::Email::MailSend',
               name => 'email',
                 to => [ qw(foo@bar.com bar@baz.org ) ],
             subject => 'Oh No!!!!!!!!!!',
          min_level => 'emerg'
   }
 ]

=item APPEND_NEWLINE

By default Log::Dispatch does not append a newline to the end of the log messages.  By setting
this option to a true value, a newline character will automatically be added to the end
of the log message.

 APPEND_NEWLINE => 1

=item LOG_METHOD_EXECUTION (EXPERIMENTAL)

This option will allow you to log the execution path of your program.  Set LOG_METHOD_EXECUTION to
a list of all the modules you want to be logged.  This will automatically send a debug message at
the start and end of each method/function that is called in the modules you listed.
The parameters passed, and the return value will also be logged.  This can be useful by tracing the
program flow in the logfile without having to resort to the debugger.

 LOG_METHOD_EXECUTION => [qw(__PACKAGE__ CGI::Application CGI)],

WARNING:  This hasn't been heavily tested, although it seems to work fine for me.  Also, a closure
is created around the log object, so some care may need to be taken when using this in a
persistent environment like mod_perl.  This feature depends on the L<Sub::WrapPackages> module.

=back

=head2 DEFAULT OPTIONS

The following example shows what options are set by default (ie this is what you
would get if you do not call log_config).  A single Log::Dispatch::Screen module that writes
error messages to STDERR with a minimum log level of debug.

 $self->log_config(
   LOG_DISPATCH_MODULES => [ 
     {        module => 'Log::Dispatch::Screen',
                name => 'screen',
              stderr => 1,
           min_level => 'debug',
      append_newline => 1
     }
   ],
 );

Here is a more customized example that uses two file appenders, and an email gateway.
Here all debug messages are sent to /tmp/debug.log, and all messages above are sent
to /tmp/messages.log.  Also, any emergency messages are emailed to foo@bar.com and 
bar@baz.org.

 $self->log_config(
   LOG_DISPATCH_MODULES => [ 
     {    module => 'Log::Dispatch::File',
            name => 'debug',
        filename => '/tmp/debug.log',
       min_level => 'debug',
       max_level => 'debug'
     },
     {    module => 'Log::Dispatch::File',
            name => 'messages',
        filename => '/tmp/messages.log',
       min_level => 'info'
     },
     {    module => 'Log::Dispatch::Email::MailSend',
            name => 'email',
              to => [ qw(foo@bar.com bar@baz.org ) ],
          subject => 'Oh No!!!!!!!!!!',
       min_level => 'emerg'
     }
   ],
   APPEND_NEWLINE => 1,
 );
 

=head1 EXAMPLE

In a CGI::Application module:

  
  # configure the log modules once during the init stage
  sub cgiapp_init {
    my $self = shift;
 
    # Configure the session
    $self->log_config(
      LOG_DISPATCH_MODULES => [ 
        {    module => 'Log::Dispatch::File',
               name => 'messages',
           filename => '/tmp/messages.log',
          min_level => 'error'
        },
        {    module => 'Log::Dispatch::Email::MailSend',
               name => 'email',
                 to => [ qw(foo@bar.com bar@baz.org ) ],
             subject => 'Oh No!!!!!!!!!!',
          min_level => 'emerg'
        }
      ],
      APPEND_NEWLINE => 1,
    );
 
  }
 
  sub cgiapp_prerun {
    my $self = shift;
 
    $self->log->debug("Current runmode:  ".$self->get_current_runmode);
  }
 
  sub my_runmode {
    my $self = shift;
    my $log  = shift;

    if ($ENV{'REMOTE_USER'}) {
      $log->info("user ".$ENV{'REMOTE_USER'});
    }

    # etc...
  }


=head1 BUGS

This is alpha software and as such, the features and interface
are subject to change.  So please check the Changes file when upgrading.


=head1 SEE ALSO

L<CGI::Application>, L<Log::Dispatch>, L<Log::Dispatch::Screen>, L<Sub::WrapPackages>, perl(1)


=head1 AUTHOR

Cees Hek <cees@crtconsulting.ca>


=head1 LICENSE

Copyright (C) 2004 Cees Hek <cees@crtconsulting.ca>

This library is free software. You can modify and or distribute it under the same terms as Perl itself.

=cut

