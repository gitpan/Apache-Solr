# Copyrights 2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
package Apache::Solr::Document;
use vars '$VERSION';
$VERSION = '0.90';


use warnings;
use strict;

use Log::Report    qw(solr);


sub new(@) { my $c = shift; (bless {}, $c)->init({@_}) }
sub init($)
{   my ($self, $args) = @_;

    $self->{ASD_boost}    = $args->{boost} // 1.0;

    $self->{ASD_fields}   = [];   # ordered
    $self->{ASD_fields_h} = {};   # grouped by name
    $self->addFields($args->{fields});
    $self;
}

#---------------

sub boost() {shift->{ASD_boost}}
sub fieldNames() { my %c; $c{$_->{name}}++ for shift->fields; sort keys %c }


sub fields(;$)
{   my $f    = shift->{ASD_fields};
    @_ or return @$f;
    my $name = shift;
    grep $_->{name} eq $name, @$f;
}


sub field($)
{   my ($f, $n) = (shift->{ASD_fields}, shift);
    first $_->{name} eq $n, @$f;
}


sub addField($$%)
{   my $self  = shift;
    my $name  = shift;
    my $field =     # important to minimalize copying of content
      { name    => $name
      , content => ( !ref $_[0]            ? shift
                   : ref $_[0] eq 'SCALAR' ? ${shift()}
                   :                         shift
                   )
      };
    my %args  = @_;
    $field->{boost} = $args{boost} || 1.0;

    push @{$self->{ASD_fields}}, $field;
    push @{$self->{ASD_fields_h}{$name}}, $field;
    $field;
}


sub addFields($%)
{   my ($self, $h, @args) = @_;
    # pass content by ref to avoid a copy of potentially huge field.
    if(ref $h eq 'ARRAY')
    {   for(my $i=0; $i < @$h; $i+=2)
        {   $self->addField($h->[$i] => \$h->[$i+1], @args);
        }
    }
    else
    {   $self->addField($_ => \$h->{$_}, @args) for sort keys %$h;
    }
}

#--------------------------

1;
