package HTTP::Tiny::CustomRetry;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Time::HiRes qw(sleep);

use parent 'HTTP::Tiny';

sub new {
    my ($class, %attrs) = @_;

    my %our_attrs;
    for (keys %attrs) {
        next unless /^retry_/;
        $our_attrs{$_} = delete $attrs{$_};
    }

    my $self = $class->SUPER::new(%attrs);
    $self->{$_} = $our_attrs{$_} for keys %our_attrs;
    $self;
}

sub request {
    my ($self, $method, $url, $options) = @_;

    # initiate backoff strategy
    unless ($self->{_backoff}) {

        my $strategy = $self->{retry_strategy} //
            $ENV{HTTP_TINY_CUSTOMRETRY_STRATEGY};
        die "Please specify retry_strategy" unless $strategy;
        my $pkg = "Algorithm::Backoff::$strategy";
        (my $pkg_pm = "$pkg.pm") =~ s!::!/!g;
        require $pkg_pm;

        my %ar_attrs;
        for (keys %ENV) {
            next unless /^HTTP_TINY_CUSTOMRETRY_(.+)/;
            next if $1 eq 'strategy';
            my $name = lc $1;
            $ar_attrs{$name} = $ENV{$_};
        }
        for (keys %$self) {
            if (/^retry_(.+)/) {
                next if $1 eq 'strategy';
                $ar_attrs{$1} = $self->{$_};
            }
        }

        $self->{_backoff} = $pkg->new(%ar_attrs);
    }

    my $res;
    while (1) {
        $res = $self->SUPER::request($method, $url, $options);
        if ($res->{status} !~ /\A[5]/) {
            $self->{_backoff}->success;
            return $res;
        }
        my $secs = $self->{_backoff}->failure;
        if ($secs == -1) {
            log_trace "Failed requesting %s (%s - %s), giving up",
                $url,
                $res->{status},
                $res->{reason};
            return $res;
        }
        log_trace "Failed requesting %s (%s - %s), retrying in %.1f second(s) (attempt #%d) ...",
            $url,
            $res->{status},
            $res->{reason},
            $secs,
            $self->{_backoff}{_attempts}+1;
        sleep $secs;
    }
    $res;
}

1;
# ABSTRACT: Retry failed HTTP::Tiny requests

=head1 SYNOPSIS

 use HTTP::Tiny::CustomRetry;

 my $res  = HTTP::Tiny::CustomRetry->new(
     retry_strategy => 'Exponential', # required, pick a strategy (which is name of submodule under Algorithm::Backoff::*)

     # the following attributes are available to customize the Exponential
     # strategy, which are attributes from Algorithm::Backoff::Exponential with
     # retry_ prefix.

     # retry_max_attempts     => ...,
     # retry_jitter_factor    => ...,
     # retry_initial_delay    => ...,
     # retry_max_delay        => ...,
     # retry_exponent_base    => ...,
     # retry_delay_on_success => ...,

 )->get("http://www.example.com/");


=head1 DESCRIPTION

This class is a subclass of L<HTTP::Tiny> that retry fail responses (a.k.a.
responses with 5xx statuses; 4xx are considered the client's fault so we don't
retry those).

It's a more elaborate version of L<HTTP::Tiny::Retry> which offers a simple
retry strategy: using a constant delay between attempts. HTTP::Tiny::CustomRetry
uses L<Algorithm::Backoff> to offer several retry/backoff strategies.


=head1 ENVIRONMENT

=head2 HTTP_TINY_CUSTOMRETRY_STRATEGY

String. Used to set default for the L</retry_strategy> attribute.

Other C<retry_ATTRNAME> attributes can also be set via environment
HTTP_TINY_CUSTOMRETRY_I<ATTRNAME>, for example C<retry_max_attempts> can be set
via HTTP_TINY_CUSTOMRETRY_MAX_ATTEMPTS.


=head1 SEE ALSO

L<Algorithm::Backoff> and C<Algorithm::Backoff::*> strategy modules.

L<HTTP::Tiny>

L<HTTP::Tiny::Retry> and L<HTTP::Tiny::Patch::Retry>, simpler retry strategy
(constant delay).

L<HTTP::Tiny::Patch::CustomRetry>, patch version of this module.
