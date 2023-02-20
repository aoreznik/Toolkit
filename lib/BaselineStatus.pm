package Table::BaselineStatus;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use Data::Dumper;
use Array::Diff;

has tablename	=> 'BaselineStatus';
has id_field	=> 'baselinestatusid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub accompanying_diseases {
	my $class = shift;
	my $id = $class->get_id;
	my $dbh = $class->{DB}->{mysql};

	my @accompanying_diseases;
	my $test_acc = Table::AccompanyingDisease->new;
	my $sql_cmd = "SELECT ".$test_acc->id_field." FROM `".$test_acc->tablename."` WHERE ".$class->id_field." = '$id';";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		push (@accompanying_diseases, Table::AccompanyingDisease->fetch($class->{DB}, $$row[0]));
		}
	return @accompanying_diseases;
	}

# Следующая сабрутина: на вход - ссылка на массив ONCOTREE кодов
# Проверяет совпадает ли список из того что подано на вход с тем что есть в базу
# Если совпадает - возвращает 0, если нет - 1
sub accompanying_diseases_difference {
	my $class	= shift;
	my $dCodes	= shift; # ссылка на массив ONCOTREE кодов
	my $reference	= [(map {$_->info->{pathologycode}} $class->accompanying_diseases)];
	
	if (defined($dCodes)) {
		$dCodes = [sort {$a cmp $b} @{$dCodes}];
		} else {
		$dCodes = [];
		}
	if (defined($reference)) {
		my $reference = [sort {$a cmp $b} @{$reference}];
		} else {
		$reference = [];
		}
	unless (Array::Diff->diff($dCodes, $reference)->count) {
		return 0;
		} else {
		return 1;
		}
	}

sub accompanying_diseases_purge {
	my $class	= shift;
	my $test_acc = Table::AccompanyingDisease->new;
	my $sql_cmd	= "DELETE FROM `".$test_acc->tablename."` WHERE ".$class->id_field."=".$class->get_id.";";
	$class->{DB}->execute($sql_cmd);
	}

sub accompanying_diseases_update {
	my $class	= shift;
	my $dCodes	= shift; # ссылка на массив ONCOTREE кодов
	my $test_acc = Table::AccompanyingDisease->new;
	if ($class->accompanying_diseases_difference($dCodes)) {
		my $added;
		my $flag = 0;
		accompanying_diseases_update_ADD:
		undef $added;
		foreach my $arg (@{$dCodes}) {
			my $info;
			$info->{($class->id_field)} = $class->get_id;
			$info->{"pathologycode"} = $arg;
			my $inserted;
			eval {$inserted = Table::AccompanyingDisease->insert_row($class->{DB}, $info)};
			if ($@) {
				foreach my $inserted_arg (@{$added}) {
					my $sql_cmd = "DELETE FROM `".$test_acc->tablename."` WHERE ".$test_acc->id_field."=$inserted_arg;";
					$class->{DB}->execute($sql_cmd);
					}
				die "Can't update accompanying disease list\n";
				} else {
				push (@{$added}, $inserted);
				}
			}
		$class->accompanying_diseases_purge if $flag eq 0;
		if ($flag eq 0) {
			$flag = 1;
			goto accompanying_diseases_update_ADD;
			}
		}
	}

sub Case {
	my $class = shift;

	return $class->{DB}->Case($class->info->{casename});
	}

sub is_completed {
	my $class = shift;
	
	my $result = 1;
	return 0 unless defined $class->info->{diagnosismain};
	return 0 unless defined $class->info->{pathologycodebaseline};
	return 0 unless defined $class->info->{diagnosisyear};
	return 0 unless defined $class->info->{tumorstatuscode};
	return 0 unless defined $class->Case->info->{profiledateyear};
	return 0 unless defined $class->Case->info->{mgttypecode};
	return 1;
	}























1;
