package AnsibleModule;

use Mojo::Base -base;
use Mojo::JSON qw/decode_json encode_json/;
use Mojo::Util qw/slurp/;
use POSIX qw/locale_h/;


has argument_spec           => sub { +{} };
has bypass_checks           => sub {0};
has no_log                  => sub {0};
has check_invalid_arguments => sub {1};
has mutually_exclusive      => sub { [] };
has required_together       => sub { [] };
has required_one_of         => sub { [] };
has supports_check_mode     => sub {0};
has required_if             => sub { [] };

has params => sub {
  my $self = shift;
  decode_json($ARGV[0] ? slurp($ARGV[0]) : "{}");

};

has _legal_inputs => sub {
  {_ansible_check_mode => 1, _ansible_no_log => 1};
};
has check_mode => sub {0};

sub new {
  my $self = shift->SUPER::new(@_);
  setlocale(LC_ALL, "");
  $self->_check_argument_spec();
  $self->_check_params();
  unless ($self->bypass_checks) {
    $self->_check_arguments();
    $self->_check_required_together();
    $self->_check_required_one_of();
    $self->_check_required_if();
  }
  $self->_log_invocation() unless $self->no_log();
  $self->_set_cwd();
  return $self;
}

sub exit_json {
  my ($self, $args) = @_;
}

sub fail_json {
  my ($self, $args) = @_;
}

sub _check_argument_spec {
  my $self = shift;
  for my $arg (keys(%{$self->argument_spec})) {
    $self->legal_inputs->{$arg}++;
    my $spec = $self->argument_spec->{$arg};
    $self->fail_json(msg =>
        "internal error: required and default are mutually exclusive for $arg")
      if defined $spec->{default} && $spec->{required};
    next unless $spec->{aliases};
    $self->fail_json(msg => "internal error: aliases must be an arrayref")
      unless ref $spec->{aliases} && ref $spec->{aliases} ne 'ARRAY';
    $self->legal_inputs->{$_}++ for @{$spec->{aliases}};
  }
}

sub _check_arguments {
  my $self = shift;

  # Check for missing required params
  my @missing = ();
  for my $arg (keys(%{$self->argument_spec})) {
    my $spec = $self->argument_spec->{$arg};
    push(@missing, $arg) if $spec->{required} && !$self->params->{$arg};
    my $choices = $spec->{choices} || [];
    $self->fail_json(msg => 'error: choices must be a list of values')
      unless ref $choices eq 'ARRAY';
    if ($self->params->{$arg}) {
      if (!grep { $self->params->{$arg} eq $_ } $choices) {
        $self->fail_json(msg => "value of $arg must be one of: "
            . join(", ", $choices)
            . ", got: "
            . $self->params->{$arg});
      }
    }
    $self->fail_json(
      msg => "missing required arguments: " . join(" ", @missing))
      if @missing;

# Try to wrangle types. We don't care as much as python does about diff scalars.
    if ($spec->{type}) {
      if ($spec->{type} eq 'dict') {
        $self->fail_json(msg => "Could not serialize $arg to dict")
          unless defined $self->params->{$arg}
            = $self->_to_dict($self->params->{$arg});

      }
      elsif ($spec->{type} eq 'list') {
        $self->fail_json(msg => "Could not serialize $arg to list")
          unless defined $self->params->{$arg}
            = $self->_to_list($self->params->{$arg});

      }
      elsif ($spec->{type} eq 'bool') {
        $self->fail_json(msg => "Could not serialize $arg to bool")
          unless defined $self->params->{$arg}
            = $self->_to_list($self->params->{$arg});
      }
      else {
        $self->fail_json(msg => "Could not serialize $arg to bool")
          if ref $self->params->{$arg}

      }
    }


    sub _to_dict {
      my ($self, $val) = @_;

      # if it's a ref we only accept hashes.
      if (ref $val) {
        return $val if ref $val eq 'HASH';
        return;

        # json literal
      }
      elsif ($val =~ /^{/) {
        my $res = decode_json($val);
        return $res if defined $res;
      }
      elsif ($val =~ /=/) {
        return {split /\s*=\s*/, split /\s*,\s*/, $arg};
      }
      return;
    }

    sub _to_list {
      my ($self, $val) = @_;

      # if it's a ref we only accept arrays.
      if (ref $val) {
        return $val if ref $val eq 'ARRAY';
        return;
      }

      # single element or split if comma separated
      return [split /[\s,]+/, $val];

    }

    sub _to_bool {
      my ($self, $val) = @_;
      return 1 if grep { lc($val) eq lc($_) } qw/yes on true 1/;
      return 0 if grep { lc($val) eq lc($_) } qw/no off false 1/;
      return undef;
    }

    sub _check_argument_types {
      my $self = shift;
    }

    sub _check_required_together {
      my $self = shift;
    }

    sub _check_required_one_of {
      my $self = shift;
    }

    sub _check_argument_types {
      my $self = shift;
    }

    sub _log_invocation {
    }

    sub _set_cwd {
    }

    sub _check_params {
      my $self = shift;
      for my $param (keys %{$self->params}) {
        if ($self->check_invalid_arguments) {
          $self->fail_json(msg => "unsupported parameter for module: $param")
            unless $self->legal_inputs->{$param};
        }
        my $val = $self->params->{$param};
        $self->no_log(!!$val) if $param eq '_ansible_no_log';
        if ($param eq '_ansible_check_mode') {
          $self->exit_json(
            skipped => 1,
            msg     => "remote module does not support check mode"
          ) unless $self->supports_check_mode;
          $self->check_mode(1);
        }

        $self->no_log(!!$val) if $param eq '_ansible_no_log';
      }
    }

    sub _count_terms {
      my ($self, $terms) = @_;
      my $count;
      for my $term (@$terms) {
        $count++ if $self->params->{$terms};
      }
    }

    1;

=head1 NAME

AnsibleModule - Port of AnsibleModule helper from Ansible distribution

=head1 SYNOPSIS

my $pkg_mod=AnsibleModule->new(argument_spec=> {
    name => { aliases => 'pkg' },
    state => { default => 'present', choices => [ 'present', 'absent'],
    list => {}
  },
  required_one_of => [ qw/ name list / ],
  mutually_exclusive => [ qw/ name list / ],
  supports_check_mode => 1,
  );
...
$pkg_mod->exit_json(changed => True, foo => 'bar');

=head1 DESCRIPTION

This is a helper class for building ansible modules in Perl. It's a straight port of the AnsibleModule class
that ships with the ansible distribution.

=head1 ATTRIBUTES

=head2 argument_spec

The argument specification for your module.

=head2 bypass_checks

=head2 no_log

=head2 check_invalid_arguments

=head2 mutually_exclusive

=head2 required_together

=head2 required_one_fo

=head2 add_file_common_args

=head2 supports_check_mode

=head2 required_if

=head1 METHODS

=head2 exit_json




=cut