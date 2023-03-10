#!/usr/bin/perl

package Atlas;

use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

use List::Util qw( min max );
use Getopt::Std;
use XML::Simple qw(:strict);
use Data::Dumper;
use DBI;
use Net::IMAP::Simple;
use Email::Simple;
use IO::Socket::SSL;
use HTML::Strip;
use Exporter;
use Switch;
use Readonly;
use experimental 'smartmatch';
use utf8;
use Encode qw(is_utf8 encode decode decode_utf8);
use Text::Unidecode;
use Test::More;
use JSON;
use Barcode;
use Patient;

our @ISA	= qw/ Exporter /;
our @EXPORT	= qw/&check_bam_file/;

sub isVariantFormat {
	my $text = shift;
	return 0 unless defined $text;
	if ($text =~ /^([^:;>]+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+)$/) {
		return "1";
		} else {
		return '0';
		}
	}

sub execute_cmd {
	my $cmd = shift;
	print STDERR "! COMMAND TASK: ",$cmd,"\n";
	print STDERR "! COMMAND OUTPUT:\n";
	print STDERR "---------------------------------\n";
	print STDERR `$cmd`;
	print STDERR "---------------------------------\n";
	}

sub isVariantRuleFormat {
	my $text = shift;
	return 0 unless defined $text;
	my $ruleDic;
	$ruleDic->{somatic} = 1;
	$ruleDic->{germline_het} = 1;
	$ruleDic->{germline_hom} = 1;
	$ruleDic->{germline_nos} = 1;
	$ruleDic->{wt} = 1;
	$ruleDic->{wt_seq} = 1;
	$ruleDic->{wt_lab} = 1;
	$ruleDic->{variant_nos} = 1;
	if ($text =~ /^([^:;>]+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+):(\S+)$/) {
		my $rule = $5;
		$rule = lc($rule);
		return 0 unless defined $ruleDic->{$rule};
		return "1";
		} else {
		return '0';
		}
	}

sub isCNVFormat {
	my $text = shift;
	return 0 unless defined $text;
	if ($text =~ /^(\S+):amp$/) {
		return 1;
		}
	if ($text =~ /^(\S+):del$/) {
		return 1;
		}
	}	

sub VCFinfo {
	#INPUT - INFO field
	my $line = shift;
	my $field = shift;
	my @info = split/;/, $line;
	foreach my $arg (@info) {
		if ($arg =~ /^$field=(\S+)$/) {
			return $1;
			}
		}
	return undef;
	}

sub VCFline {
	#INPUT - whole VCF line
	my $line = shift;
	my @mas = split/\t/, $line;
	$line = $mas[7];
	my $field = shift;
	my @info = split/;/, $line;
	foreach my $arg (@info) {
		if ($arg =~ /^$field=(\S+)$/) {
			return $1;
			}
		}
	return undef;
	}

sub current_time {
	my $format = shift;;
	my $now = DateTime->now(time_zone => 'Europe/Moscow');
	return $now->strftime('%F') unless defined $format;
	if (lc($format) eq 'date') {
		return $now->strftime('%F');
		} elsif (lc($format) eq 'datetime') {
		return $now->strftime('%Y-%m-%d %H:%M:%S');
		} else {
		return $now->strftime('%F');
		}
	}

sub uppercase {
	my $string = shift;
	my %abc = (
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??",
		"a"=>"A","b"=>"B","c"=>"C","d"=>"D",
		"e"=>"E","f"=>"F","g"=>"G","h"=>"H",
		"i"=>"I","j"=>"J","k"=>"K","l"=>"L",
		"m"=>"M","n"=>"N","o"=>"O","p"=>"P",
		"q"=>"Q","r"=>"R","s"=>"S","t"=>"T",
		"u"=>"U","v"=>"V","w"=>"W","x"=>"X",
		"y"=>"Y","z"=>"Z");
	$string = uc($string);
	foreach my $letter (keys %abc) {
		$abc{$letter} = encode('utf8', $abc{$letter});
		my $letter_d = encode('utf8', $letter);
		#$string =~ s/$letter_d/$abc{$letter}/g;
		#print STDERR "$letter_d\n";
		if ($string =~ /$letter/) {
			print "FOUND\n";
			}
		}
	$string = decode('utf8', $string);
	return $string;
	}

sub uppercase_firstOnly {
	my $string = shift;
        my %abc = (
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??",
                "a"=>"A","b"=>"B","c"=>"C","d"=>"D",
                "e"=>"E","f"=>"F","g"=>"G","h"=>"H",
                "i"=>"I","j"=>"J","k"=>"K","l"=>"L",
                "m"=>"M","n"=>"N","o"=>"O","p"=>"P",
                "q"=>"Q","r"=>"R","s"=>"S","t"=>"T",
                "u"=>"U","v"=>"V","w"=>"W","x"=>"X",
                "y"=>"Y","z"=>"Z",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??",
		"A"=>"A","B"=>"B","C"=>"C","D"=>"D",
		"E"=>"E","F"=>"F","G"=>"G","H"=>"H",
		"I"=>"I","J"=>"J","K"=>"K","L"=>"L",
		"M"=>"M","N"=>"N","O"=>"O","P"=>"P",
		"Q"=>"Q","R"=>"R","S"=>"S","T"=>"T",
		"U"=>"U","V"=>"V","W"=>"W","X"=>"X",
		"Y"=>"Y","Z"=>"Z");
	my @letters = split//, decode('utf8', $string);
	$letters[0] = $abc{$letters[0]};
	$string = join("", @letters);
        return $string;
        }

sub wrap_python {
	my $cmd = shift;
	for (my $i = 1; $i < 50; $i++) {
		my $result = `$cmd 2>&1`;
		if (($result =~ /(httplib.ResponseNotReady)/)or($result =~ /(httplib2.ServerNotFoundError)/)or($result =~ /(Traceback \(most recent call last\))/)or($result =~ /(HttpError)/)) {
			sleep(15);
			print STDERR "TRY $i failed $1\n";
			print STDERR "$cmd\n";
			print STDERR $result;
			next;
			}
		return $result;
		}
	return undef;
	}

sub reformat_date {
	my $string = shift;
	my @data = split/-/, $string;
	return join(".", ($data[2], $data[1], $data[0]));
	}

sub struct_compare { # deep comparison of data structures
	my $d1 = shift;
	my $d2 = shift;
	return 0 unless ((ref $d1) eq (ref $d2));
	if (ref $d1 eq 'HASH') {
		return 0 unless eq_array([sort {$a cmp $b} keys %{$d1}], [sort {$a cmp $b} keys %{$d2}]);
		foreach my $key (keys %{$d1}) {
			return 0 unless struct_compare($d1->{$key}, $d2->{$key});
			}
		} elsif (ref $d1 eq 'ARRAY') {
		return 0 unless ((scalar @{$d1}) eq (scalar @{$d2}));
		my %reserved;
		for (my $i = 0; $i < scalar @{$d1}; $i++) {
			for (my $j = 0; $j < scalar @{$d2}; $j++) {
				next if defined $reserved{$j};
				if (struct_compare($d1->[$i], $d2->[$j])) {
					$reserved{$j} = 1;
					}
				}
			}
		if ((scalar (keys %reserved)) eq (scalar @{$d2})) {
			return 1;
			} else {
			return 0;
			}
		} else {
		return ($d1 eq $d2 ? 1 : 0);
		}
	return 1;
	}

sub lowercase {
        my $string = shift;
        my %abc = (
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
		"??"=>"??","??"=>"??","??"=>"??","??"=>"??",
                "??"=>"??");
        $string = lc($string);
        $string = decode('utf8' ,$string);
        foreach my $letter (keys %abc) {
                $string =~ s/$letter/$abc{$letter}/g;
                }
        return encode('utf8', $string);
        }


sub barcode_ident {
	my $barcode = shift;
	my $DB = $barcode->{DB};
	my $patient = Patient->fetch($DB, $barcode->info->{patientid});
	my $case    = Case->fetch($DB,
		$barcode->info->{patientid} . "-" . $barcode->info->{caseid});
	my $message = '';
	$message = $patient->info->{patientfamilyname};
	$message = $patient->info->{patientgivenname} unless defined $message;
	$message = "$message " if defined $message;
	if ((defined($case->{internalbarcode}))and(defined($case->{internalbarcode}->{internalbarcodeid}))) {
		$message = $message . $case->{internalbarcode}->{internalbarcodeid};
		}
	$message = ($message || "") . " " . $barcode->info->{panelcode};
	$message = decode('utf8', $message);
	return $message;
	}

sub check_bam_file {
	my @args = @_;
	my $samtools = $args[0]->{software}->{'samtools'};
	
	my $log = `$samtools quickcheck -qv @args[1..(scalar @args - 1)] 2>&1`;
	return 1 unless defined $log;
	chomp $log;
	
	if (length($log) > 0) {
		return 1;
		} else {
		return 0;
		}
	}

sub check_date_format {
	my $date = shift;
	my $f = 0;
	if ($date =~ /^(\d{4}-(\d{2})-(\d{2}))$/) {
		my $year = $1;
		my $month = $2;
		my $day = $3;
		if ($day > 31) {
			return 1;
			}
		if ($month > 12) {
			return 1;
			}
		} else {
		return 1;
		}
	
	return 0;
	}

sub prepare_str_for_insert {
	my $str = shift;
	unless (defined($str)) {
		return 'NULL';
		}
	if (uc($str) eq 'NULL') {
		return $str;
		}
	if ($str =~ /^'(.*)'$/) {
		$str = $1;
		}
	$str = "'" . decode('utf8' ,$str) . "'";
	return $str;
	}

sub parse_case {
	my $str = shift;
	my $patient_id;
	my $case_id;
	if ($str =~ /(\d+)-(\d{2})/) {
		$patient_id = $1;
		$case_id = $2;
		}
	return ($patient_id, $case_id);
	}

sub parse_barcode {
	my $str = shift;
	my $pt_id;
	my $case_id;
	my $b_id;
	if ($str =~ /(\d+)-(\d{2})-(\d{2})/) {
		$pt_id = $1;
		$case_id = $2;
		$b_id = $3;
		}
	return ($pt_id, $case_id, $b_id);
	}

sub slim_id {
	my $id = shift;
	if ($id =~ /([123456789]+)/) {
		$id = $1;
		}
	return $id;
	}
	
sub grep_patient_id {
	my $str = shift;
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})-(\S{2})$/) {
		return $1;
		}
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})$/) {
		return $1;
		}
	if ($str =~ /^(\d+)-(\d{2})$/) {
		return $1;
		}
	if ($str =~ /^(\d+)$/) {
		return $1;
		}

	}
		
sub grep_case_id {
	my $str = shift;
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})-(\S{2})$/) {
		return $2;
		}
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})$/) {
		return $2;
		}
	if ($str =~ /^(\d+)-(\d{2})$/) {
		return $2;
		}
	}

sub grep_barcode_id {
	my $str = shift;
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})-(\S{2})$/) {
		return $3;
		}
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})$/) {
		return $3;
		}
	}

sub grep_analysis_id {
	my $str = shift;
	if ($str =~ /^(\d+)-(\d{2})-(\d{2})-(\S{2})$/) {
		return $4;
		}
	}

sub decode_email {
	my %abc = ('=D0=B0'=>'??', '=D0=B1'=>'??', '=D0=B2'=>'??', '=D0=B3'=>'??', '=D0=B4'=>'??', '=D0=B5'=>'??', '=D1=91'=>'??', '=D0=B6'=>'??', '=D0=B7'=>'??', '=D0=B8'=>'??', '=D0=B9'=>'??', '=D0=BA'=>'??', '=D0=BB'=>'??', '=D0=BC'=>'??', '=D0=BD'=>'??', '=D0=BE'=>'??', '=D0=BF'=>'??', '=D1=80'=>'??', '=D1=81'=>'??', '=D1=82'=>'??', '=D1=83'=>'??', '=D1=84'=>'??', '=D1=85'=>'??', '=D1=86'=>'??', '=D1=87'=>'??', '=D1=88'=>'??', '=D1=89'=>'??', '=D1=8A'=>'??', '=D1=8B'=>'??', '=D1=8C'=>'??', '=D1=8D'=>'??', '=D1=8E'=>'??', '=D1=8F'=>'??', '=D0=90'=>'??', '=D0=91'=>'??', '=D0=92'=>'??', '=D0=93'=>'??', '=D0=94'=>'??', '=D0=95'=>'??', '=D0=81'=>'??', '=D0=96'=>'??', '=D0=97'=>'??', '=D0=98'=>'??', '=D0=99'=>'??', '=D0=9A'=>'??', '=D0=9B'=>'??', '=D0=9C'=>'??', '=D0=9D'=>'??', '=D0=9E'=>'??', '=D0=9F'=>'??', '=D0=A0'=>'??', '=D0=A1'=>'??', '=D0=A2'=>'??', '=D0=A3'=>'??', '=D0=A4'=>'??', '=D0=A5'=>'??', '=D0=A6'=>'??', '=D0=A7'=>'??', '=D0=A8'=>'??', '=D0=A9'=>'??', '=D0=AA'=>'??', '=D0=AB'=>'??', '=D0=AC'=>'??', '=D0=AD'=>'??', '=D0=AE'=>'??', '=D0=AF'=>'??');
	my $str = shift;
	foreach my $key (keys %abc) {
		$str =~ s/$key/$abc{$key}/g;
		}
	return $str;
	}

sub decode_KOI7_N1 {
	my %abc = ('\x{44E}' => '??','\x{430}' => '??','\x{431}' => '??','\x{446}' => '??','\x{434}' => '??','\x{435}' => '??','\x{444}' => '??','\x{433}' => '??','\x{445}' => '??','\x{438}' => '??','\x{439}' => '??','\x{43A}' => '??','\x{43B}' => '??','\x{43C}' => '??','\x{43D}' => '??','\x{43E}' => '??','\x{43F}' => '??','\x{44F}' => '??','\x{440}' => '??','\x{441}' => '??','\x{442}' => '??','\x{443}' => '??','\x{436}' => '??','\x{432}' => '??','\x{44C}' => '??','\x{44B}' => '??','\x{437}' => '??','\x{448}' => '??','\x{44D}' => '??','\x{449}' => '??','\x{447}' => '??','\x{44A}' => '??','\x{42E}' => '??','\x{410}' => '??','\x{411}' => '??','\x{426}' => '??','\x{414}' => '??','\x{415}' => '??','\x{424}' => '??','\x{413}' => '??','\x{425}' => '??','\x{418}' => '??','\x{419}' => '??','\x{41A}' => '??','\x{41B}' => '??','\x{41C}' => '??','\x{41D}' => '??','\x{41E}' => '??','\x{41F}' => '??','\x{42F}' => '??','\x{420}' => '??','\x{421}' => '??','\x{422}' => '??','\x{423}' => '??','\x{416}' => '??','\x{412}' => '??','\x{42C}' => '??','\x{42B}' => '??','\x{417}' => '??','\x{428}' => '??','\x{42D}' => '??','\x{429}' => '??','\x{427}' => '??','\x{21}' => '!','\x{22}' => '"','\x{23}' => '#','\x{A4}' => '??','\x{25}' => '%','\x{26}' => '&','\x{27}' => "'",'\x{28}' => '(','\x{29}' => ')','\x{2A}' => '*','\x{2B}' => '+','\x{2C}' => ',','\x{2D}' => '-','\x{2E}' => '.','\x{2F}' => '/','\x{30}' => '0','\x{31}' => '1','\x{32}' => '2','\x{33}' => '3','\x{34}' => '4','\x{35}' => '5','\x{36}' => '6','\x{37}' => '7','\x{38}' => '8','\x{39}' => '9','\x{3A}' => ':','\x{3B}' => ';','\x{3C}' => '<','\x{3D}' => '=','\x{3E}' => '>','\x{3F}' => '?');
	my $str = shift;
	foreach my $key (keys %abc) {
		$str =~ s/$key/$abc{$key}/g;
		}
	return $str;
	}

sub recognizeMutationEvent {
	my $var_name = shift;
	my $chr;
	my $pos;
	my $ref;
	my $alt;
	if ($var_name =~ /(\S+):(\d+)(\S+)>(\S+)/) {
		$chr = $1;
		$pos = $2;
		$ref = $3;
		$alt = $4;
		} else {
		die "Can't parse variation name: $var_name\n";
		}
	my $event_type_d;
	if ((length($ref) eq 1)and(length($alt) eq 1)) {
		$event_type_d = 'SNP';
		} elsif ((length($ref) > 1)and(length($alt) eq 1)) {
		$event_type_d = 'deletion';
		} elsif ((length($ref) eq 1)and(length($alt) > 1)) {
		$event_type_d = 'insertion';
		} else {$event_type_d = 'MNP';}
	return $event_type_d;
	}

sub file_to_json {
	my $json_file = shift;
	open (JSONREAD, "<$json_file") or die $!;
	my $json_data = do {local $/; <JSONREAD>} or die $!;
	close JSONREAD or die $!;
	my $json;
	$json = JSON::XS->new->ascii->decode($json_data) or die $!;
	return $json;
	}

sub data_to_json {
	my $data = shift;
	my $json = JSON::XS->new->ascii->decode($data) or die $!;
	return $json;
	}

sub json_to_data {
	my $json = shift;
	my $data = JSON::XS->new->encode($json);
	return $data;
	}

sub json_to_file {
	my $json = shift;
	my $file = shift;
	
	my $json_data = JSON::XS->new->pretty->encode($json);
	open (WRITEJSON, ">$file") or die "Cant open $file for write";
	print WRITEJSON $json_data;
	close WRITEJSON;
	
	return 0;
	}

sub parse_log {
	my $log_file = shift;
	if (open(my $fh, "<", $log_file)) {
		my $log = `tail -n1 $log_file`;
		chomp $log;
		if ($log =~ /Exit\s+status\s+1/) {
			return 1;
			}
		close $fh;
		} else {
		my @log_data = split/\n/, $log_file;
		my $log = $log_data[scalar (@log_data) - 1];
		chomp $log;
		if ($log =~ /Exit\s+status\s+1/) {
			if ($log =~ /Exit\s+status\s+1/) {
				return 1;
				}
			}
		}
	return 0;
	}		

sub decode_content {
	my $content = shift;
	my $content_decoded;
	foreach my $key (keys %{$content}) {
		my $key_d = encode('utf8', $key);
		my $val_d = encode('utf8', $content->{$key});
		$content_decoded->{$key_d} = lc($val_d);
		}
	return $content_decoded;
	}

sub parse_log_content {
	my $log_string = shift;
	my @lines = split/\n/, $log_string;
	if ($lines[scalar @lines - 1] =~ /Exit\s+status\s+1/) {
		return 1;
		}
	return 0;
	}

sub undef_to_null {
	my $info = shift;
	foreach my $key (keys %{$info}) {
		$info->{$key} = 'NULL' unless defined($info->{$key});
		}
	}

sub null_to_undef {
	my $info = shift;
	foreach my $key (keys %{$info}) {
		next unless defined($info->{$key});
		if (lc($info->{$key}) eq 'null') {
			undef $info->{$key};
			}
		}
	}

sub var_name {
	my $chr = shift;
	my $pos = shift;
	my $ref = shift;
	my $alt = shift;
	unless (defined($pos)) {
		if ($chr =~ /(\S+):(\d+)(\S+)>(\S+)/) {
			$chr = $1;
			$pos = $2;
			$ref = $3;
			$alt = $4;
			} else {return undef}
		}
	$chr =~ tr/C/c/;
	$chr =~ tr/H/h/;
	$chr =~ tr/R/r/;
	if ($chr =~ /chr/) {
		} else {
		$chr = "chr$chr";
		}
	$ref = uc($ref);
	$alt = uc($alt);
	return "$chr:$pos$ref>$alt";
	}

# ?????????????????? ?????? ???????????????? ???????????????????????? ???????????????????????? ???????? ??????????.
# ???????????????????????? ?????? ???????? ?????????? ?????????????????? ?????? ?????????? ???????? ?? ?????????????? (????????????????, $barcode->info) ???????????????????? ???? ???????????????????????? ??????????
# ???????????????????? ?????? ?? ?????????????? ???????????????? ?????????? ????????. ???????? ?????? ???????????? - ???????????? ?????????????? ???????? ???? ??????????????????
sub check_info_diff {
	my $DB			= shift;
	my $table_name		= shift;
	my $info_new		= shift;
	my $info_reference	= shift;
	Atlas::null_to_undef($info_new);
	my $hash_result;
	my $field_dic;
	foreach my $arg ($DB->get_table_field_dic($table_name)) {
		$arg = lc($arg);
		$field_dic->{$arg} = 1;
		}
	foreach my $key (keys %{$info_new}) {
		unless (defined($field_dic->{lc($key)})) {
			delete $info_new->{$key} unless defined $field_dic->{$key};
			}
		}
	foreach my $key (keys %{$info_reference}) { # ?????????????????? ?????? ?????? ?????????????????? ???????? ?????????????????? ??????????
		unless (defined $info_new->{$key}) {
			if (defined($info_reference->{$key})) {
				$hash_result->{$key} = undef;
				}
			next;
			}
		if (defined $info_reference->{$key}) {
			next if lc($info_new->{$key}) eq lc($info_reference->{$key});
			$hash_result->{$key} = $info_new->{$key};
			}
		}
	foreach my $key (keys %{$info_new}) { # ?????????????????? ?????? ?????? ?????????? ??????????
		next if defined($info_reference->{$key});
		next unless defined($info_new->{$key});
		$hash_result->{$key} = $info_new->{$key};
		}
	Atlas::undef_to_null($info_new);
	return $hash_result;
	}

sub parse_content {
	my $content = shift;
	my $PARSE_DIC = shift;
	# ?????????????????????????????? ??????????????
	foreach my $column (keys %{$PARSE_DIC->{"ranaming:::rules"}}) {
		next unless (defined($content->{SPREADSHEET}->{$column}));
		$content->{SPREADSHEET}->{$PARSE_DIC->{"ranaming:::rules"}->{$column}}
			= $content->{SPREADSHEET}->{$column};
	}
	foreach my $column (keys %{$PARSE_DIC->{"column::DIC"}}) {
		next unless defined($content->{SPREADSHEET}->{$column});
		my $value = $content->{SPREADSHEET}->{$column};
		$value = lc($value);
		#die "Unknown $column code - required\n" unless defined($PARSE_DIC->{"column::DIC"}->{$column}->{$value});
		if (defined($PARSE_DIC->{"column::DIC"}->{$column}->{$value})) {
			$content->{SPREADSHEET}->{$column} = $PARSE_DIC->{"column::DIC"}->{$column}->{$value};
			}
	}
	# ???????????? ????????
	foreach my $column (keys %{$PARSE_DIC->{"split::dates"}}) {
		my $prefix = $PARSE_DIC->{"split::dates"}->{$column}->{prefix};
		my $value = $content->{SPREADSHEET}->{$column};
		$value =~ s/^\s+|\s+$//g;
		if ($value =~ /^(\d\d\d\d)\.(\d{1,2})\.(\d{1,2})$/) {
			$content->{SPREADSHEET}->{$prefix."year"} = int($1);
			$content->{SPREADSHEET}->{$prefix."month"} = int($2);
			$content->{SPREADSHEET}->{$prefix."day"} = int($3);
		} elsif ($value =~ /^(\d\d\d\d)\.(\d{1,2})$/) {
			$content->{SPREADSHEET}->{$prefix."year"} = int($1);
			$content->{SPREADSHEET}->{$prefix."month"} = int($2);
		} elsif ($value =~ /^(\d\d\d\d)$/) {
			$content->{SPREADSHEET}->{$prefix."year"} = int($1);
		} elsif (lc($value) eq 'n/a') {
		} elsif (lc($value) eq 'na') {
		} elsif (lc($value) eq '') {
		} else {die "Wow wow wow, maaan.. Have you read how to fill date columns??? (see $column)"}
	}
	# ???????????? ?????????????????? ?????????????? (???????? ?????????????? = ???????? ????????????????)
	foreach my $column (keys %{$PARSE_DIC->{"tablename:single"}}) {
		my $value = $content->{SPREADSHEET}->{$column};
		$value = "NULL" unless defined($value);
		$value =~ s/^\s+|\s+$//g;
		$value = "NULL" if lc($value) eq 'na';
		$value = "NULL" if lc($value) eq 'n/a';
		$value = "NULL" if $value eq '';
		$content->{$PARSE_DIC->{"tablename:single"}->{$column}}->{$column} = $value;
	}
	foreach my $column (keys %{$PARSE_DIC->{"tablename:multiple"}}) {
		my $value = $content->{SPREADSHEET}->{$column};
		next unless defined($value);
		next if lc($value) eq 'n/a';
		next if lc($value) eq 'na';
		next if $value eq '';
		$value = [split/;|,/, $value];
		map {$_ =~ s/^\s+|\s+$//g} @{$value};
		$content->{$PARSE_DIC->{"tablename:multiple"}->{$column}} = $value;
	}
	return $content;
}



sub format_VAF {
	my $input = shift;
	if ($input < 0.05) {
		$input = int($input*1000)/10;
		} else {
		$input = int($input*100);
		}
	return $input;
	}












