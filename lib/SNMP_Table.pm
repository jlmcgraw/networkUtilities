### SNMP_Table.pm
###
### Convenience routines for dealing with SNMP tables
###
### Author:        Simon Leinen  <simon@switch.ch>
### Date created:  24-Apr-2005
###
### Tables are a central concept to SNMP (or, more precisely, of the
### SMI or Structure of Management Instrumentation).  SNMP tables are
### conceptually similar to tables in relational database management
### systems (RDBMS).  Each SNMP table has at least one conceptual
### columns, of which at least one serve as an index columns.
###
### This little library implements a form of "object-relational
### mapping", or rather, a "relational-object mapping" from SNMP
### tables to Perl objects.
###
### In particular, they convert SNMP table rows into Perl objects, and
### allow a user to store these objects into some composite structure
### based on the index(es).

package SNMP_Table;

require 5.004;

use strict;
use vars qw(@ISA @EXPORT $VERSION);
use Exporter;

use SNMP_util;

@ISA = qw(Exporter);

@EXPORT = qw(snmp_rows_to_objects snmp_row_to_object snmp_map_row_objects);

### snmp_rows_to_objects TARGET, CLASS, PREFIX, COLUMNS...
###
### Returns a reference to a hash that maps a table's index to objects
### created from the set of COLUMNS.  The COLUMNS are partial OID
### names, to each of which the PREFIX is prepended.  An object is
### created for each row in the table, by creating a hash reference
### with a slot for each column, named by the (partial) column name.
### It is blessed to the CLASS.
###
### For example, if we have the following table at $TARGET:
###
### index fooBar fooBaz fooBlech
###
### 1000  asd    23498  vohdajae
### 1001  fgh    45824  yaohetoo
### 1002  jkl    89732  engahghi
###
### Then the call:
###
###  snmp_rows_to_objects ($TARGET, 'MyFoo', 'foo', 'bar', 'baz', 'blech')
###
### will create a hash reference similar to this:
###
###     $result = {};
###     $result{1000} = bless { 'bar' => 'asd',
###                             'baz' => 23498,
###                             'blech' => 'vohdajae' }, 'MyFoo';
###     $result{1001} = bless { 'bar' => 'fgh',
###                             'baz' => 45824,
###                             'blech' => 'yaohetoo' }, 'MyFoo';
###     $result{1002} = bless { 'bar' => 'jkl',
###                             'baz' => 89732,
###                             'blech' => 'engahghi' }, 'MyFoo';
###
sub snmp_rows_to_objects ($$$@) {
    my ( $target, $class, $prefix, @cols ) = @_;
    my $result = {};
    snmp_map_row_objects(
        $target, $class,
        sub () {
            my ( $index, $object ) = @_;
            $result->{$index} = $object;
        },
        $prefix,
        @cols
    );
    return $result;
}

### snmp_map_row_objects TARGET, CLASS, MAPFN, PREFIX, COLUMNS...
###
### This function traverses a table, creating an object for each row,
### and applying the user-supplied MAPFN to each of these objects.
###
### The table is defined by PREFIX and COLUMNS, as described for
### snmp_rows_to_objects above.  An object is created according to
### CLASS and COLUMNS, as described above.  The difference is that,
### rather than putting all objects in a hash, we simply apply the
### user-supplied MAPFN to each row object.
###
sub snmp_map_row_objects ($$$$@) {
    my ( $target, $class, $mapfn, $prefix, @cols ) = @_;
    my @coloids = map ( $prefix . ucfirst $_, @cols );
    my @slotnames = @cols;
    snmpmaptable(
        $target,
        sub () {
            my ( $index, @colvals ) = @_;
            my $object = bless { 'index' => $index }, $class;
            foreach my $slotname (@slotnames) {
                $object->{$slotname} = shift @colvals;
            }
            &$mapfn( $index, $object );
        },
        @coloids
    );
}

### snmp_row_to_object TARGET, CLASS, INDEX, PREFIX, COLUMNS...
###
### This can be used if one is only interested in a single row,
### defined by INDEX.  This function uses a large SNMP get request to
### retrieve all columns of interest, and assembles the result into a
### hash blessed to CLASS.  This hash directly represents the row
### object.  Note that this function returns just a single hash, as
### opposed to snmp_rows_to_objects, which returns a hash that maps
### index values to such hashes.
###
sub snmp_row_to_object ($$$$@ ) {
    my ( $target, $class, $index, $prefix, @cols ) = @_;
    my @coloids = map ( $prefix . ucfirst $_ . "." . $index, @cols );
    my @result = snmpget( $target, @coloids );
    my %result = ();
    foreach my $col (@cols) {
        $result{$col} = shift @result;
    }
    bless \%result, $class;
    return \%result;
}

1;
