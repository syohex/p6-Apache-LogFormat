use v6;

class Apache::LogFormat::Logger{

has &!callback;
has &!logger;

method new-with-logger(&callback, $logger) {
    if $logger.defined {
        return self.bless(:&callback, :$logger);
    }
    return self.bless(:&callback);
}

method new(&callback) {
    return self.new-with-logger(&callback, Nil);
}

submethod BUILD(:&!callback, :&!logger) { }

method log-line(Apache::LogFormat::Logger:D: %env, @res) {
    my &logger = &!logger;
    if !&logger {
        &logger = sub ($m) {
            %env<p6sgi.error>.print($m)
        };
    }

    if !%env<p6sgi.error> {
        %env<p6sgi.error> = $*ERR;
    }

    # TODO: provide proper parameters to callback
    my $time = DateTime.now();
    &logger(&!callback(%env, @res, Nil, Nil, $time));
}

}

class Apache::LogFormat::Compiler {

has %.char-handlers = (
    '%' => q!'%'!,
    b => q|(defined($length)??$length!!'-')|,
    h => q!(%env<REMOTE_ADDR> || '-')!,
    l => q!'-'!,
    u => q!(%env<REMOTE_USER> || '-')!,
    t => q!'[' ~ format-datetime($time) ~ ']'!,
    r => q!safe-value(%env<REQUEST_METHOD>) ~ " " ~ safe-value(%env<REQUEST_URI>) ~ " " ~ %env<SERVER_PROTOCOL>!,
    s => q!@res[0]!,
    m => q!safe-value(%env<REQUEST_METHOD>)!,
    U => q!safe-value(%env<PATH_INFO>)!,
    q => q|(%env<QUERY_STRING> ?? '?' ~ safe-value(%env<QUERY_STRING>) !! '')|,
    H => q!%env<SERVER_PROTOCOL>!,
);

has %.block-handlers;

# [10/Oct/2000:13:55:36 -0700]
my sub format-datetime(DateTime $dt) {
    state @abbr = <Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec>;

    return sprintf("%02d/%s/%04d:%02d:%02d:%02d %s%02d%02d",
        $dt.day-of-month, @abbr[$dt.month-1], $dt.year,
        $dt.hour, $dt.minute, $dt.second, ($dt.offset>0??'+'!!'-'), $dt.offset/3600, $dt.offset%3600);
}

our sub safe-value($s) {
    if !defined($s) {
        return '';
    }

    my $x = $s.Str;
    $x ~~ s:g/(<:C>)/{ "\\x" ~ Blob.new(ord($0)).unpack("H*") }/;
    return $x;
}

our sub string-value($s) {
    if !$s {
        return '-'
    }

    my $x = $s.Str;
    $x ~~ s:g/(<:C>)/{ "\\x" ~ Blob.new(ord($0)).unpack("H*") }/;
    return $x;
}

method run-block-handler($block, $type, $extra) {
    state %psgi-reserved = (
        CONTENT_LENGTH => 1,
        CONTENT_TYPE => 1,
    );
    my $cb;
    given $type {
        when 'i' {
            $cb = $block;
            $cb ~~ s:g/\-/_/;
            my $hdr-name = $cb.uc;
            if !%psgi-reserved{$hdr-name} {
                $hdr-name = "HTTP_" ~ $hdr-name;
            }
            $cb = q!string-value(%env<! ~ $hdr-name ~ q!>)!;
        }
        default {
            die "oops"
        }
    }
    return q|! ~ | ~ $cb ~ q| ~ q!|;
}

method run-char-handler(Str $char, $extra) {
    my $cb = %.char-handlers{$char};
    if !$cb {
        die "char handler for '$char' undefined";
    }
    return q|! ~ | ~ $cb ~ q|
      ~ q!|;
}

method compile (Apache::LogFormat::Compiler:D: $pat, :$logger) {
    my $fmt = $pat; # copy so we can safely modify

    $fmt ~~ s:g/'!'/'\''!'/;
    $fmt ~~ s:g!
        [
             \%\{ $<name>=.+? \} $<type>=<[ a..z A..Z ]>|
             \%<[\<\>]>? $<char>=<[ a..z A..Z \%]>
        ]
    !{ $<name> ?? self.run-block-handler($<name>, $<type>, Nil) !! self.run-char-handler($<char>.Str, Nil) }!;


    $fmt = q~sub (%env, @res, $length, $reqtime, DateTime $time = DateTime.now) {
        q!~ ~ $fmt ~ q~!;
    }~;
    my $code = EVAL($fmt);
    return Apache::LogFormat::Logger.new-with-logger($code, $logger)
}

}

class Apache::LogFormat {

method common(Apache::LogFormat:U: :$logger) {

    my $p = Apache::LogFormat::Compiler.new();
    return $p.compile('%h %l %u %t "%r" %>s %b');
}

method combined(Apache::LogFormat:U: :$logger) {
    my $p = Apache::LogFormat::Compiler.new();
    return $p.compile('%h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-agent}i"');
}

}




=begin pod

=head1 NAME

Apache::LogFormat::Compiler - blah blah blah

=head1 SYNOPSIS

  use Apache::LogFormat::Compiler;

=head1 DESCRIPTION

Apache::LogFormat::Compiler is ...

=head1 AUTHOR

Daisuke Maki <lestrrat@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Daisuke Maki

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
