#!/usr/bin/perl
#
# Example implementation for the Git filter protocol version 2
# See Documentation/gitattributes.txt, section "Filter Protocol"
#

use strict;
use warnings;

my $MAX_PACKET_CONTENT_SIZE = 65516;

sub packet_bin_read {
    my $buffer;
    my $bytes_read = read STDIN, $buffer, 4;
    if ( $bytes_read == 0 ) {

        # EOF - Git stopped talking to us!
        exit();
    }
    elsif ( $bytes_read != 4 ) {
        die "invalid packet size '$bytes_read' field";
    }
    my $pkt_size = hex($buffer);
    if ( $pkt_size == 0 ) {
        return ( 1, "" );
    }
    elsif ( $pkt_size > 4 ) {
        my $content_size = $pkt_size - 4;
        $bytes_read = read STDIN, $buffer, $content_size;
        if ( $bytes_read != $content_size ) {
            die "invalid packet ($content_size expected; $bytes_read read)";
        }
        return ( 0, $buffer );
    }
    else {
        die "invalid packet size";
    }
}

sub packet_txt_read {
    my ( $res, $buf ) = packet_bin_read();
    unless ( $buf =~ /\n$/ ) {
        die "A non-binary line SHOULD BE terminated by an LF.";
    }
    return ( $res, substr( $buf, 0, -1 ) );
}

sub packet_bin_write {
    my ($packet) = @_;
    print STDOUT sprintf( "%04x", length($packet) + 4 );
    print STDOUT $packet;
    STDOUT->flush();
}

sub packet_txt_write {
    packet_bin_write( $_[0] . "\n" );
}

sub packet_flush {
    print STDOUT sprintf( "%04x", 0 );
    STDOUT->flush();
}

( packet_txt_read() eq ( 0, "git-filter-client" ) ) || die "bad initialize";
( packet_txt_read() eq ( 0, "version=2" ) )         || die "bad version";
( packet_bin_read() eq ( 1, "" ) )                  || die "bad version end";

packet_txt_write("git-filter-server");
packet_txt_write("version=2");

( packet_txt_read() eq ( 0, "clean=true" ) )  || die "bad capability";
( packet_txt_read() eq ( 0, "smudge=true" ) ) || die "bad capability";
( packet_bin_read() eq ( 1, "" ) )            || die "bad capability end";

packet_txt_write("clean=true");
packet_txt_write("smudge=true");
packet_flush();

while (1) {
    my ($command)  = packet_txt_read() =~ /^command=([^=]+)$/;
    my ($pathname) = packet_txt_read() =~ /^pathname=([^=]+)$/;

    packet_bin_read();

    my $input = "";
    {
        binmode(STDIN);
        my $buffer;
        my $done = 0;
        while ( !$done ) {
            ( $done, $buffer ) = packet_bin_read();
            $input .= $buffer;
        }
    }

    my $output;
    if ( $command eq "clean" ) {
        ### Perform clean here ###
        $output = $input;
    }
    elsif ( $command eq "smudge" ) {
        ### Perform smudge here ###
        $output = $input;
    }
    else {
        die "bad command '$command'";
    }

    packet_txt_write("status=success");
    packet_flush();
    while ( length($output) > 0 ) {
        my $packet = substr( $output, 0, $MAX_PACKET_CONTENT_SIZE );
        packet_bin_write($packet);
        if ( length($output) > $MAX_PACKET_CONTENT_SIZE ) {
            $output = substr( $output, $MAX_PACKET_CONTENT_SIZE );
        }
        else {
            $output = "";
        }
    }
    packet_flush();    # flush content!
    packet_flush();    # empty list!
}
