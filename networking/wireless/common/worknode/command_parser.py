#!/usr/bin/python
# Copyright (c) 2014 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Ken Benoit

"""
The worknode.command_parser module provides standard base classes
(KeyValueParser, SingleValueParser, TableParser, and TableRowParser) for all
command parser classes to inherit from.

"""

__author__ = 'Ken Benoit'

import re

import framework

class CommandParserFactory(framework.Framework):
    """
    CommandParserFactory provides a factory class that automatically provides
    the requested parser object.

    """
    def __init__(self):
        super(CommandParserFactory, self).__init__()

    def get_parser(self, output_type):
        """
        Get a parser object of the requested type.

        Keyword arguments:
        output_type - Type of parser object needed ("key-value", "table",
                      "table-row", "single").

        Return value:
        Parser object.

        """
        parser = None

        if output_type == 'key-value':
            parser = KeyValueParser()
        elif output_type == 'table':
            parser = TableParser()
        elif output_type == 'single':
            parser = SingleValueParser()
        elif output_type == 'table-row':
            parser = TableRowParser()
        return parser

    def __repr__(self):
        return '{module}.{class_name}()'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
        )

class KeyValueParser(framework.Framework):
    """
    KeyValueParser provides a standard base to create parser objects for a
    PropertyManager object to use when refreshing properties in key-value
    format.

    """
    def __init__(self):
        super(KeyValueParser, self).__init__()
        self.__regex_list = []

    def parse_raw_output(self, output):
        """
        Parse the raw output being supplied by using the predefined parsing
        routine.

        Keyword arguments:
        output - Raw output in list format.

        Return value:
        Dictionary of the properties with their assigned values.

        """
        property_dictionary = {}
        for line in output:
            for regex in self.__regex_list:
                match = re.search(regex, line)
                if match:
                    property_key = match.group('property_key')
                    property_value = match.group('property_value')
                    property_dictionary[property_key] = property_value

        return property_dictionary

    def add_regular_expression(self, regex):
        """
        Add a regular expression to search for when parsing the command output.
        It needs to be in the format of (?P<property_key>) and
        (?P<property_value>) for the grouping of the regular expression matches
        so that the property name and value can be parsed out correctly.

        Keyword arguments:
        regex - Regular expression with groupings for the property name and the
                property value.

        """
        self.__regex_list.append(regex)

    def __repr__(self):
        return '{module}.{class_name}()'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
        )

class SingleValueParser(framework.Framework):
    """
    SingleValueParser provides a standard base to create parser objects for a
    PropertyManager object to use when refreshing properties in single value
    format (basically raw output).

    """
    def __init__(self):
        super(SingleValueParser, self).__init__()
        self.__export_key = ''
        self.__regex = None

    def parse_raw_output(self, output):
        """
        Parse the raw output being supplied by using the predefined parsing
        routine.

        Keyword arguments:
        output - Raw output in list format.

        Return value:
        Dictionary of the properties with their assigned values.

        """
        property_dictionary = {}
        output_string = ''.join(output)
        if self.__regex is not None:
            match = re.search(self.__regex, output_string)
            if match:
                output_string = match.groups()[0]
                property_dictionary[self.__export_key] = output_string
            else:
                property_dictionary[self.__export_key] = None
        return property_dictionary

    def set_export_key(self, key):
        """
        Set the key to associate with the parsed value that way parse_raw_output
        still returns a dictionary.

        Keyword arguments:
        key - Key to associate with the property value parsed out.

        """
        self.__export_key = key

    def set_regex(self, regex):
        """
        Set the regex that should be used on the output while it is being
        parsed. Whatever is in the first grouping will be what is returned as
        the property value when parsed.

        Keyword arguments:
        regex - Regular expression to use when parsing, and whatever is in the
                first grouping is what will be returned.

        """
        self.__regex = regex

    def __repr__(self):
        return '{module}.{class_name}()'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
        )

class TableParser(framework.Framework):
    """
    TableParser provides a standard base to create parser objects for a
    PropertyManager object to use when refreshing properties from table output.

    """
    def __init__(self):
        super(TableParser, self).__init__()
        self.__regex_list = []
        self.__column_titles = []

    def set_column_titles(self, titles):
        """
        Set the titles of the columns of the table.

        Keyword arguments:
        titles - List of column titles.

        """
        self.__column_titles = titles

    def parse_raw_output(self, output):
        """
        Parse the raw output being supplied by using the predefined parsing
        routine.

        Keyword arguments:
        output - Raw output in list format.

        Return value:
        List of the dictionaries of the properties with their assigned values.

        """
        property_row_list = []
        for line in output:
            for regex in self.__regex_list:
                match = re.search(regex, line)
                if match:
                    row_dictionary = {}
                    for column_title in self.__column_titles:
                        try:
                            row_dictionary[column_title] = match.group(column_title)
                        except IndexError:
                            continue
                        except Exception as e:
                            raise e
                    property_row_list.append(row_dictionary)

        return property_row_list

    def add_regular_expression(self, regex):
        """
        Add a regular expression to search for when parsing the command output.
        It needs to be in the format of (?P<column_title>) for the grouping of
        the regular expression matches so that the column value can be parsed
        out correctly.

        Keyword arguments:
        regex - Regular expression with groupings for the column title.

        """
        self.__regex_list.append(regex)

    def __repr__(self):
        return '{module}.{class_name}()'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
        )

class TableRowParser(framework.Framework):
    """
    TableRowParser provides a standard base to create parser objects for a
    PropertyManager object to use when refreshing properties from a specific row
    in table output.

    """
    def __init__(self):
        super(TableRowParser, self).__init__()
        self.__regex_list = []
        self.__column_titles = []
        self.__requested_column_title = None
        self.__requested_column_value = None

    def set_column_titles(self, titles):
        """
        Set the titles of the columns of the table.

        Keyword arguments:
        titles - List of column titles.

        """
        self.__column_titles = titles

    def set_specified_row(self, column_title, column_value):
        """
        Set the column title and the value under that column that should be
        matched against to find a specific row in the table.

        Keyword arguments:
        column_title - Title of the column to look for.
        column_value - Value in the specified column to look for.

        """
        self.__requested_column_title = column_title
        self.__requested_column_value = column_value

    def parse_raw_output(self, output):
        """
        Parse the raw output being supplied by using the predefined parsing
        routine.

        Keyword arguments:
        output - Raw output in list format.

        Return value:
        Dictionary of the properties with their assigned values.

        """
        property_row_list = []
        for line in output:
            for regex in self.__regex_list:
                match = re.search(regex, line)
                if match:
                    row_dictionary = {}
                    for column_title in self.__column_titles:
                        group_dict = match.groupdict()
                        if column_title in group_dict:
                            row_dictionary[column_title] = match.group(column_title)
                    property_row_list.append(row_dictionary)
                    break
        property_row = {}
        for row in property_row_list:
            if row[self.__requested_column_title] == self.__requested_column_value:
                property_row = row
        return property_row

    def add_regular_expression(self, regex):
        """
        Add a regular expression to search for when parsing the command output.
        It needs to be in the format of (?P<column_title>) for the grouping of
        the regular expression matches so that the column value can be parsed
        out correctly.

        Keyword arguments:
        regex - Regular expression with groupings for the column title.

        """
        self.__regex_list.append(regex)

    def __repr__(self):
        return '{module}.{class_name}()'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
        )
