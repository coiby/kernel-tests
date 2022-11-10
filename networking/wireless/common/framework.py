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
The framework module provides a standard base class (Framework) for all
framework classes to inherit from.

"""

__author__ = 'Ken Benoit'

import logging
import logging.config
import os
import time

import singleton

class Framework(object):
    """
    Framework provides a standard base for all classes requiring unified logging
    support.

    """
    def __init__(self):
        self.__logger = Logger.Instance().get_logger()

    def get_logger(self):
        """
        Get the framework logger.

        Return value:
        logging.Logger object.

        """
        if not self.__logger:
            self.__logger = Logger.Instance().get_logger()

        return self.__logger

    def __del__(self):
        self.__logger = None
        self = None

# This makes the Logger a singleton so that regardless of the object inheriting
# from the Framework class that we will only ever have one instance of the
# Logger.
@singleton.Singleton
class Logger(object):
    """
    Logger provides unified logging support to any Framework-based classes. The
    Logger is a Singleton so there will only ever be one instance of it.

    """
    def __init__(self):
        # Read the logging config from a config file if it exists
        if os.path.isfile('pythonlogging.conf'):
            logging.config.fileConfig('pythonlogging.conf')
            self.__logger = logging.getLogger('root')
        # Otherwise perform all the logging config from this method
        else:
            self.__logger = logging.getLogger('root')
            self.__logger.setLevel(logging.DEBUG)
            file_handler = logging.FileHandler(filename = 'test.log', mode = 'w')
            file_handler.setLevel(logging.DEBUG)
            console_handler = logging.StreamHandler()
            console_handler.setLevel(logging.DEBUG)
            formatter = logging.Formatter('%(asctime)s %(levelname)s - '
                + '%(module)s %(funcName)s line %(lineno)s: %(message)s')
            file_handler.setFormatter(formatter)
            console_handler.setFormatter(formatter)
            self.__logger.addHandler(file_handler)
            self.__logger.addHandler(console_handler)

    def get_logger(self):
        """
        Get the actual logger object.

        Return value:
        logging.Logger object.

        """
        return self.__logger

