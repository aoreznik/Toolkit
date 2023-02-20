package Table::ActiveSubstance;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use List::MoreUtils qw(uniq);
my $local_path = __DIR__ . '/';

has tablename	=> 'ActiveSubstance';
has id_field	=> 'activesubstanceid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub fetch_info_INN {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		die "Id field for table is not defined\n" unless defined $id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	my $sql_cmd = "select " . join(", ", @fields) . " from `".$class->tablename."` where activeSubstanceName = '$id'";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		++$counter;
		for (my $i = 0; $i < scalar @fields; $i++) {
			$info{$fields[$i]} = encode('utf8', $$row[$i])
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the ",$class->id_field," $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub fetch_info_Synonym {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		die "Id field for table is not defined\n" unless defined $id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	map {$_ = "`".$class->tablename."`.$_"} @fields;
	my $sql_cmd = "select " . join(", ", @fields) . " from `".$class->tablename."` INNER JOIN ActiveSubstanceSynonym ON ActiveSubstanceSynonym.activeSubstanceId = ActiveSubstance.activeSubstanceId where synonym = '$id'";
	map {$_ =~ s/`//g} @fields;
	my $tablename = $class->tablename;
	map {$_ =~ s/$tablename\.//g} @fields;
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		++$counter;
		for (my $i = 0; $i < scalar @fields; $i++) {
			$info{$fields[$i]} = encode('utf8', $$row[$i])
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the ",$class->id_field," $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;

	my $self = $class->new;
	$self->connect($DB);
	$self->fetch_info($id);
	unless (defined($self->get_id)) {
		$self->fetch_info_INN($id);
		}
	unless (defined($self->get_id)) {
		$self->fetch_info_Synonym($id);
		}
	eval {$self->get_id};
	if ($@) {
		print STDERR "$@" if $verbose;
		return undef;
		} else {
		if (defined $self->get_id) {
			return $self;
			} else {
			print STDERR "Could not fetch data from table",$class->tablename,"\n" if $verbose;
			return undef;
			}
		}
	}

sub drugRegistration_raw {
	my $class = shift;
	my $name = $class->info->{'activesubstancename'};
	my $response = Atlas::wrap_python("python $local_path/../../scripts/python/SS_Pharm_reg_parse.py $name"); # Копируется sheet из шаблона
	$response = [split/\n/, $response];
	my $i = 0;
	my $data;
	$data->{FDA} = $response->[0];
	$data->{EMA} = $response->[1];
	$data->{GRLS} = $response->[2];
	foreach my $Domain (qw(FDA EMA GRLS)) {
		next unless defined $data->{$Domain};
		if ($data->{$Domain} eq 'NA') {
			$data->{$Domain} = [];
			next;
			}
		$data->{$Domain} = [split/;/, $data->{$Domain}];
		$data->{$Domain} = [grep {$class->{DB}->Pathology($_)} @{$data->{$Domain}}];
		}
	return $data;
	}

sub drug_is_registered {
	my $class = shift;
	my $domain = shift; # FDA/EMA/GRLS
	my $disease = shift; # oncotree code
	my $data = $class->drugRegistration_raw->{$domain};
	foreach my $code (@{$data}) {
		return 1 if $class->{DB}->Pathology($disease)->find_distance_up($code) >= 0;
		}
	return 0;
	}

sub drugDescription_raw {
	my $class = shift;
	my $name = $class->info->{'activesubstancename'};
	my $response = Atlas::wrap_python("python $local_path/../../scripts/python/SS_Pharm_desc_parse.py $name"); # Копируется sheet из шаблона
	$response = [split/\n/, $response];
	my $i = 0;
	my @data;
	while (defined($response->[$i])) {
		if ($response->[$i] eq '!DISEASE') {
			++$i;
			my $code = lc($response->[$i]);
			++$i;
			++$i;
			my $description = [];
			while (1) {
				last if $response->[$i] eq '!END';
				push @{$description}, $response->[$i];
				#$description = $description.$response->[$i];
				++$i;
				}
			$description = join("<br>", @{$description});
			push @data, {
				"code" => $code,
				"desc" => $description
				}
			}
		++$i;
		}
	return \@data;
	}

sub drugDescription_select {
	my $class = shift;
	my $target = shift; #Disease code
	my $data = $class->drugDescription_raw;
	return (((sort {
		$class->{DB}->Pathology($target)->find_distance_up($a->{code})
		<=>
		$class->{DB}->Pathology($target)->find_distance_up($b->{code})}
		grep {$class->{DB}->Pathology($target)->find_distance_up($_->{code}) > -1}
		@{$class->drugDescription_raw})[0])
		|| undef);
	}	






























1;
