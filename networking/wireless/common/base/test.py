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
The test module provides a standard base class (Test) for all tests to inherit
from.

"""

__author__ = 'Ken Benoit'

import optparse
import time
import random
import traceback

import framework
import base.exported_file_factory
from constants.testcodes import *
from constants.testmessages import *
from constants.time import *
from base.exception.test import *

class Test(framework.Framework):
    """
    Test provides a standard base for all test classes.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.__option_parser = optparse.OptionParser()
        self.__command_line_arguments = {
            'named_arguments': {},
            'extra_arguments': [],
        }
        self.__configure_command_line_options()
        self.__random_module = random
        self.__test_name = None
        self.__author = None
        self.__author_email = None
        self.__test_description = None
        self.__test_step_list = TestStepList()
        self.__external_test_blocks = {}

    def __configure_command_line_options(self):
        # Define the dry run command line option
        self.add_command_line_option(
            '-d',
            '--dryRun',
            dest = 'dry_run',
            action = 'store_true',
            default = False,
            help = 'put the test into dry run mode where the test steps will '
                + 'be listed but the actual step execution will not be '
                + 'performed',
        )
        # Define the steps command line option
        self.add_command_line_option(
            '-s',
            '--step',
            dest = 'step',
            action = 'append',
            type = 'int',
            help = 'step number to perform. can be supplied multiple times to '
                + 'indicate the order of the steps to perform',
        )
        # Define the simulated failure command line option
        self.add_command_line_option(
            '-f',
            '--simulateFailure',
            dest = 'fail_step',
            action = 'store',
            type = 'int',
            help = 'step number to simulate a failure at. the failure will be '
                + 'triggered at the end of the step indicated, after execution '
                + 'has taken place',
        )
        # Define the random number generator seed command line option
        self.add_command_line_option(
            '-r',
            '--randomSeed',
            dest = 'seed',
            action = 'store',
            default = int(time.time()),
            help = 'seed to feed to the random number generator in order to '
                + 'have reproducible random results',
        )
        # Define the export command line option
        self.add_command_line_option(
            '-x',
            '--export',
            dest = 'export',
            action = 'store',
            help = 'export the test steps to the format requested',
        )
        # Define the master log level override command line option
        self.add_command_line_option(
            '-l',
            '--logLevelOverride',
            dest = 'log_level_override',
            action = 'store',
            type = 'int',
            help = 'logging level to use for the console and log file output '
                + 'instead of the default or the one indicated in the '
                + 'configuration file. the value should be given as a number '
                + 'that indicates the lowest level of logging wanted, with all '
                + 'the upper levels of logging getting used as well. the lower '
                + 'the number the more logging. 10 = debug, 20 = info, 30 = '
                + 'warning, 40 = error, 50 = critical.',
        )

    def set_test_name(self, name):
        """
        Set the name of the test.

        Keyword arguments:
        name - Name of the test.

        """
        self.__test_name = name

    def get_test_name(self):
        """
        Get the name of the test.

        Return value:
        Name of the test.

        """
        return self.__test_name

    def set_test_author(self, name, email = None):
        """
        Set the author of the test.

        Keyword arguments:
        name - Name of the author.
        email - Email address of the author.

        """
        self.__author = name
        self.__author_email = email

    def get_test_author(self):
        """
        Get the name of the test author.

        Return value:
        Name of the test author.

        """
        return self.__author

    def get_test_author_email(self):
        """
        Get the email address of the test author.

        Return value:
        Email address of the test author.

        """
        return self.__author_email

    def set_test_description(self, description):
        """
        Set a brief description of the test.

        Keyword arguments:
        description - A brief description of the test.

        """
        self.__test_description = description

    def get_test_description(self):
        """
        Get the short description of the test.

        Return value:
        Short description of the test.

        """
        return self.__test_description

    def get_test_step_list(self):
        """
        Get the test step list object.

        Return value:
        TestStepList object.

        """
        return self.__test_step_list

    def get_random_module(self):
        """
        Get the random generator module.

        Return value:
        The Python random module.

        """
        return self.__random_module

    def get_command_line_option_parser(self):
        """
        Get the command line option parser.

        Return value:
        OptionParser object.

        """
        return self.__option_parser

    def add_test_step(
        self,
        test_step,
        test_step_description = None,
        rollback_step = None,
        rollback_step_description = None
        ):
        """
        Add a test step (and optionally a rollback step) to the test.

        Keyword arguments:
        test_step - Function or instance method to add as a test step.
        test_step_description - Optional description string of the test step.
        rollback_step - Optional function or instance method to run in the case
                        of the test failing. Rollback steps will only be run if
                        the test step it is attached to has been run.
        rollback_step_description - Optional description string of the rollback
                                    step.

        """
        self.get_test_step_list().add_test_step(
            test_step = test_step,
            test_step_description = test_step_description,
            rollback_step = rollback_step,
            rollback_step_description = rollback_step_description,
        )

    def clear_test_steps(self):
        """
        Clear the list of currently defined test steps.

        """
        self.get_test_step_list().clear_list()

    def _external_list_name_exists(self, name):
        if name in list(self.__external_test_blocks.keys()):
            return True
        return False

    def create_external_test_list(self, name):
        """
        Creates an empty named external test list that can be used to reuse
        other tests from within this test.

        Keyword arguments:
        name - Name of the external test list (used for referring to the list
               later).

        """
        if self._external_list_name_exists(name = name):
            raise KeyError("External test list '{0}' already exists")
        self.__external_test_blocks[name] = TestList()

    def add_external_test_to_test_list(
        self,
        test,
        command_line_arguments,
        list_name
        ):
        """
        Add an external test to a named test list.

        Keyword arguments:
        test - Test object.
        command_line_arguments - List of command line arguments to supply to the
                                 test.
        list_name - Name of the external test list.

        """
        if not self._external_list_name_exists(name = list_name):
            self.create_external_test_list(name = list_name)
        self.__external_test_blocks[list_name].add_test(
            test = test,
            command_line_arguments = command_line_arguments,
        )

    def export(self, export_format):
        """
        Export the test steps out to a file of the requested format.

        Keyword arguments:
        export_format - Format to export the test steps out to.

        """
        exported_file = base.exported_file_factory.ExportedFileFactory().get_exported_file(
            file_format = export_format,
            test = self,
        )
        exported_file.write()

    def __parse_command_line_arguments(self, command_line_arguments = None):
        parser = self.get_command_line_option_parser()
        options = None
        args = None
        if command_line_arguments is not None:
            (options, args) = parser.parse_args(args = command_line_arguments)
        else:
            (options, args) = parser.parse_args()
        self.__command_line_arguments['extra_arguments'] = args
        for option_object in parser.option_list:
            dest = option_object.dest
            if dest is not None:
                if hasattr(options, dest):
                    value = getattr(options, dest)
                    self.__set_command_line_argument(dest = dest, value = value)

    def add_command_line_option(self, *args, **kwargs):
        """
        Add a command line option.

        Keyword arguments:
        Passthrough arguments for the add_option() method for OptionParser.

        """
        parser = self.get_command_line_option_parser()
        option_object = parser.add_option(*args, **kwargs)
        self.__set_command_line_argument(dest = option_object.dest)

    def __set_command_line_argument(self, dest, value = None):
        self.__command_line_arguments['named_arguments'][dest] = value

    def get_command_line_option_value(self, dest):
        """
        Get the value of a command line option using the dest name.

        Keyword arguments:
        dest - Destination name set when adding the command line option.

        Return value:
        Value of the command line option.

        """
        return self.__command_line_arguments['named_arguments'][dest]

    def get_extra_command_line_arguments(self):
        """
        Get the list of extra command line arguments provided outside of option
        flags.

        Return value:
        List of extra command line arguments.

        """
        return self.__command_line_arguments['extra_arguments']

    def run_test(
        self,
        dry_run = None,
        steps = None,
        simulated_fail_step = None,
        random_seed = None,
        command_line_arguments = None,
        ):
        """
        Run the test going through all added test steps sequentially. If an
        exception is encountered during any of the test steps then the rollback
        steps will be run in reverse order for all of the test steps that have
        been run.

        Keyword arguments:
        dry_run - It True then the test will be run in a dry run mode where the
                  steps will be moved through without actually running the code
                  in the test step.
        steps - If a list of step numbers is provided then the test will be run
                in the order provided.
        simulated_fail_step - If a step number is provided then a simulated
                              failure will be triggered after the test step has
                              been executed.
        random_seed - If a value is provided then this will be the value that is
                      used to seed the random number generator.
        command_line_arguments - List of command line arguments as they would be
                                 supplied on the command line to the script.

        Return value:
        Integer exit code indicating the result of the test run.

        """
        start_time = None
        end_time = None
        start_time = time.time()
        # Parse the command line options
        self.__parse_command_line_arguments(
            command_line_arguments = command_line_arguments,
        )

        logger = self.get_logger()

        # See if we need to override the log level settings
        log_override = self.get_command_line_option_value(
            dest = 'log_level_override',
        )
        if log_override is not None:
            logger.setLevel(log_override)

        export = self.get_command_line_option_value(dest = 'export')

        # If export is chosen then export the test steps out to the requested
        # format
        if export is not None:
            try:
                self.export(export_format = export)
            except Exception as e:
                result_message = str(e)
                result = TEST_RESULT_FAIL
                exit_code = FAIL_EXIT_CODE
                exception_type = type(e)
                # Log the exception
                logger.error(
                    "EXCEPTION ({0}): {1}".format(
                        exception_type,
                        result_message,
                    )
                )
                # Log the traceback information
                logger.debug(traceback.format_exc())

        # Adjust any base Test execution based on the command line options
        # Activate dry run mode if it is set
        if dry_run is None:
            dry_run = self.get_command_line_option_value(dest = 'dry_run')
        # Set the random number generator seed
        if random_seed is None:
            random_seed = self.get_command_line_option_value(dest = 'seed')
            random_module = self.get_random_module()
            random_module.seed(random_seed)
        # If steps is not defined then go with the default sequential order
        if steps is None:
            if self.get_command_line_option_value(dest = 'step') is None:
                steps = range(
                    self.get_test_step_list().get_number_of_test_steps()
                )
            else:
                steps = self.get_command_line_option_value(dest = 'step')
        # Set the simulated failure step number (if applicable)
        if simulated_fail_step is None:
            simulated_fail_step = self.get_command_line_option_value(
                dest = 'fail_step',
            )

        exit_code = PASS_EXIT_CODE
        result = TEST_RESULT_PASS
        result_message = None
        test_step_number_stack = []

        # Sanity check the steps first
        for step_number in steps:
            try:
                self.get_test_step_list().get_test_step(
                    step_number = step_number,
                )
            except IndexError:
                result_message = INVALID_TEST_STEP_INDEX
                result = TEST_RESULT_ABORT
                exit_code = FAIL_EXIT_CODE
                logger.error("EXCEPTION: {0}".format(result_message))
            except TypeError:
                result_message = INVALID_TEST_STEP_TYPE
                result = TEST_RESULT_ABORT
                exit_code = FAIL_EXIT_CODE
                logger.error("EXCEPTION: {0}".format(result_message))
            except Exception as e:
                exception_message = str(e)
                result_message = UNEXPECTED_EXCEPTION + ' ' + exception_message
                result = TEST_RESULT_ABORT
                exit_code = FAIL_EXIT_CODE
                # Log the exception
                logger.critical("EXCEPTION: {0}".format(result_message))
                # Log the traceback information
                logger.debug(traceback.format_exc())

        if exit_code is not FAIL_EXIT_CODE and export is None:
            logger.debug("Random seed: {0}".format(random_seed))
            # Run through the test steps
            test_step_list = self.get_test_step_list()
            for step_number in steps:
                test_step_number_stack.append(step_number)
                # Log the test step number
                logger.debug("Test step {0}".format(step_number))
                # Log the step description if it exists
                description = test_step_list.get_test_step_description(
                    step_number = step_number,
                )
                if description is not None:
                    logger.info(
                        "Test step description: {0}".format(description)
                    )

                # Run the test step (if this isn't a dry run)
                try:
                    if not dry_run:
                        test_step_list.get_test_step(
                            step_number = step_number,
                        )()
                    if step_number is simulated_fail_step:
                        raise TestFailure(
                            "Simulated failure at test step {0}".format(
                                step_number,
                            )
                        )
                except KeyboardInterrupt:
                    result_message = KEYBOARD_INTERRUPT
                    result = TEST_RESULT_ABORT
                    exit_code = FAIL_EXIT_CODE
                    logger.error("EXCEPTION: ({0})".format(result_message))
                except Exception as e:
                    result_message = str(e)
                    result = TEST_RESULT_FAIL
                    exit_code = FAIL_EXIT_CODE
                    exception_type = type(e)
                    # Log the exception
                    logger.error(
                        "EXCEPTION ({0}): {1}".format(
                            exception_type,
                            result_message,
                        )
                    )
                    # Log the traceback information
                    logger.debug(traceback.format_exc())
                # Check to see if we have failed
                if exit_code is FAIL_EXIT_CODE:
                    break

            # Run through the rollback steps if we have failed
            if exit_code is FAIL_EXIT_CODE:
                test_step_number_stack.reverse()
                test_step_list = self.get_test_step_list()
                for step_number in test_step_number_stack:
                    if test_step_list.get_rollback_step(step_number = step_number) is not None:
                        logger.debug(
                            "Rolling back test step {0}".format(step_number)
                        )
                        # Log the rollback step description if it exists
                        description = test_step_list.get_rollback_step_description(
                            step_number = step_number,
                        )
                        if description is not None:
                            logger.info(
                                "Rollback step description: {0}".format(
                                    description,
                                )
                            )
                        # Run the rollback step
                        try:
                            if not dry_run:
                                test_step_list.get_rollback_step(
                                    step_number = step_number,
                                )()
                        except Exception as e:
                            exception_message = str(e)
                            exception_type = type(e)
                            # Log the exception
                            logger.error(
                                "EXCEPTION ({0}): {1}".format(
                                    exception_type,
                                    exception_message,
                                )
                            )
                            # Log the traceback information
                            logger.debug(traceback.format_exc())
        end_time = time.time()

        # Log the test result
        logger.info("Test Result: {0}".format(result))
        logger.info(
            "Start Time: {0}".format(time.asctime(time.localtime(start_time)))
        )
        logger.info(
            "End Time: {0}".format(time.asctime(time.localtime(end_time)))
        )
        total_time = int(end_time - start_time)
        days = total_time // DAY
        hours = (total_time - (days * DAY)) // HOUR
        minutes = (total_time - (days * DAY) - (hours * HOUR)) // MINUTE
        seconds = total_time - (days * DAY) - (hours * HOUR) - (minutes * MINUTE)
        logger.info(
            "Elapsed Time: {days}d:{hours}h:{minutes}m:{seconds}s ({total_time} total seconds)".format(
                days = days,
                hours = hours,
                minutes = minutes,
                seconds = seconds,
                total_time = total_time,
            )
        )
        if result_message is not None:
            # Log the test message if available
            logger.info("Test message: {0}".format(result_message))
        return exit_code

    def __del__(self):
        del(self.__option_parser)
        self.__test_name = None
        self.__author = None
        self.__author_email = None
        self.__test_description = None
        del(self.__test_step_list)
        for key in self.__external_test_blocks.keys():
            del(self.__external_test_blocks[key])
        del(self.__external_test_blocks)
        super(Test, self).__del__()

class TestStepList(framework.Framework):
    """
    TestStepList represents a list of test steps to execute in order.

    """
    def __init__(self):
        super(TestStepList, self).__init__()
        self.__test_steps = []

    def get_test_step(self, step_number):
        """
        Get the test step given the step number.

        Keyword arguments:
        step_number - Number of the test step.

        Return value:
        Test step method.

        """
        return self.__test_steps[step_number].get_test_step()

    def get_rollback_step(self, step_number):
        """
        Get the rollback step given the step number.

        Keyword arguments:
        step_number - Number of the test step.

        Return value:
        Rollback step method.

        """
        return self.__test_steps[step_number].get_rollback_step()

    def get_test_step_description(self, step_number):
        """
        Get the description of the test step given the step number.

        Keyword arguments:
        step_number - Number of the test step.

        Return value:
        Test step description.

        """
        return self.__test_steps[step_number].get_step_description()

    def get_rollback_step_description(self, step_number):
        """
        Get the description of the rollback step given the step number.

        Keyword arguments:
        step_number - Number of the test step.

        Return value:
        Rollback step description.

        """
        return self.__test_steps[step_number].get_rollback_step_description()

    def set_test_step(self, step_number, method):
        """
        Set the test step method given the step number.

        Keyword arguments:
        step_number - Number of the test step.
        method - Test step method.

        """
        self.__test_steps[step_number].set_test_step(method = method)

    def set_rollback_step(self, step_number, method):
        """
        Set the rollback step method given the step number.

        Keyword arguments:
        step_number - Number of the test step.
        method - Rollback step method.

        """
        self.__test_steps[step_number].set_rollback_step(method = method)

    def set_test_step_description(self, step_number, description):
        """
        Set the description of the test step given the step number.

        Keyword arguments:
        step_number - Number of the test step.
        description - Description of the test step.

        """
        self.__test_steps[step_number].set_step_description(
            description = description,
        )

    def set_rollback_step_description(self, step_number, description):
        """
        Set the description of the rollback step given the step number.

        Keyword arguments:
        step_number - Number of the test step.
        description - Description of the rollback step.

        """
        self.__test_steps[step_number].set_rollback_description(
            description = description,
        )

    def add_test_step(
        self,
        test_step,
        test_step_description = None,
        rollback_step = None,
        rollback_step_description = None
        ):
        """
        Add a test step (and optionally a rollback step) to the end of the test
        list.

        Keyword arguments:
        test_step - Function or instance method to add as a test step.
        test_step_description - Optional description string of the test step.
        rollback_step - Optional function or instance method to run in the case
                        of the test failing. Rollback steps will only be run if
                        the test step it is attached to has been run.
        rollback_step_description - Optional description string of the rollback
                                    step.

        """
        test_step = TestStep(
            test_step = test_step,
            test_step_description = test_step_description,
            rollback_step = rollback_step,
            rollback_step_description = rollback_step_description
        )
        self.__test_steps.append(test_step)

    def remove_test_step(self, step_number):
        """
        Remove a test step at the indicated step number.

        Keyword arguments:
        step_number - Number of the test step.

        """
        test_step = self.__test_steps.pop(step_number)
        del(test_step)

    def insert_test_step(
        self,
        step_number,
        test_step,
        test_step_description = None,
        rollback_step = None,
        rollback_step_description = None,
        ):
        """
        Add a test step (and optionally a rollback step) before the indicated
        step of the test list.

        Keyword arguments:
        step_number - Number of the test step to insert this step before.
        test_step - Function or instance method to add as a test step.
        test_step_description - Optional description string of the test step.
        rollback_step - Optional function or instance method to run in the case
                        of the test failing. Rollback steps will only be run if
                        the test step it is attached to has been run.
        rollback_step_description - Optional description string of the rollback
                                    step.

        """
        test_step = TestStep(
            test_step = test_step,
            test_step_description = test_step_description,
            rollback_step = rollback_step,
            rollback_step_description = rollback_step_description
        )
        self.__test_steps.insert(step_number, test_step)

    def get_number_of_test_steps(self):
        """
        Get the number of steps in the list.

        Return value:
        Number of steps in the list.

        """
        return len(self.__test_steps)

    def __len__(self):
        return self.get_number_of_test_steps()

    def clear_list(self):
        """
        Remove all the test steps in the list.

        """
        while len(self.__test_steps) > 0:
            test_step = self.__test_steps.pop()
            del(test_step)

    def __del__(self):
        self.clear_list()
        del(self.__test_steps)
        super(TestStepList, self).__del__()

class TestStep(framework.Framework):
    """
    TestStep represents a test step and its associated rollback step, and
    descriptions for both.

    """
    def __init__(
        self,
        test_step,
        test_step_description = None,
        rollback_step = None,
        rollback_step_description = None,
        ):
        super(TestStep, self).__init__()
        self.__test_step_method = test_step
        self.__test_step_description = test_step_description
        self.__rollback_step_method = rollback_step
        self.__rollback_step_description = rollback_step_description

    def get_test_step(self):
        """
        Get the test step method.

        Return value:
        Test step method.

        """
        return self.__test_step_method

    def get_step_description(self):
        """
        Get the test step description.

        Return value:
        Test step description.

        """
        return self.__test_step_description

    def get_rollback_step(self):
        """
        Get the rollback step method.

        Return value:
        Rollback step method.

        """
        return self.__rollback_step_method

    def get_rollback_step_description(self):
        """
        Get the rollback step description.

        Return value:
        Rollback step description.

        """
        return self.__rollback_step_description

    def set_test_step(self, method):
        """
        Set the test step method.

        Keyword arguments:
        method - Test step method.

        """
        self.__test_step_method = method

    def set_step_description(self, description):
        """
        Set the test step description.

        Keyword arguments:
        description - Test step description.

        """
        self.__test_step_description = description

    def set_rollback_step(self, method):
        """
        Set the rollback step method.

        Keyword arguments:
        method - Rollback step method.

        """
        self.__rollback_step_method = method

    def set_rollback_step_description(self, description):
        """
        Set the rollback step description.

        Keyword arguments:
        description - Rollback step description.

        """
        self.__rollback_step_description = description

    def __del__(self):
        del(self.__test_step_method)
        del(self.__rollback_step_method)
        super(TestStep, self).__del__()

class TestList(framework.Framework):
    """
    TestStep represents a list of Test objects to run.

    """
    def __init__(self):
        super(TestList, self).__init__()
        self.__tests = []

    def get_test(self, test_number):
        """
        Get the test given the test number.

        Keyword arguments:
        test_number - Number of the test.

        Return value:
        Test object.

        """
        return self.__tests[test_number]['test']

    def get_test_arguments(self, test_number):
        """
        Get the test command line arguments given the test number.

        Keyword arguments:
        test_number - Number of the test.

        Return value:
        List of command line arguments for the test.

        """
        return self.__tests[test_number]['command_line_arguments']

    def add_test(self, test, command_line_arguments = None):
        """
        Add a test to the end of the test list.

        Keyword arguments:
        test - Test object.
        command_line_arguments - List of command line arguments to provide to
                                 the test.

        """
        if type(test) is not Test:
            raise TypeError("test argument needs to be a Test object")
        if command_line_arguments is not None and type(command_line_arguments) is not list:
            raise TypeError(
                "command_line_arguments argument needs to be a list",
            )
        test_entry_dict = {
            'test': test,
            'command_line_arguments': command_line_arguments,
        }
        self.__tests.append(test_entry_dict)

    def remove_test(self, test_number):
        """
        Remove a test at the indicated step number.

        Keyword arguments:
        test_number - Number of the test.

        """
        test_entry_dict = self.__tests.pop(test_number)
        del(test_entry_dict['test'])
        del(test_entry_dict)

    def get_number_of_tests(self):
        """
        Get the number of tests in the list.

        Return value:
        Number of tests in the list.

        """
        return len(self.__tests)

    def clear_list(self):
        """
        Remove all the tests in the list.

        """
        while len(self.__tests) > 0:
            test_entry_dict = self.__tests.pop()
            del(test_entry_dict['test'])
            del(test_entry_dict)

    def __len__(self):
        return self.get_number_of_tests()

    def __del__(self):
        self.clear_list()
        del(self.__tests)
        super(TestList, self).__del__()
