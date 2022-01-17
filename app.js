/*
 * (C) Copyright IBM Corp. 2021.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
 * an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */
const createError = require('http-errors');
const express = require('express');
const path = require('path');
const cookieParser = require('cookie-parser');
const session = require('express-session');
const helmet = require('helmet');
const nocache = require("nocache");

const indexRouter = require('./routes/index');
const flightBookingRouter = require('./routes/flights');
const airportsRouter = require('./routes/airports');

const defaultDirectives = helmet.contentSecurityPolicy.getDefaultDirectives();
delete defaultDirectives['upgrade-insecure-requests'];

const app = express();
app.use(helmet.hidePoweredBy());
app.use(helmet.frameguard());
app.use(helmet.noSniff());
app.use(nocache());
app.use(
  helmet.contentSecurityPolicy({
    directives: {
      ...defaultDirectives,
      "script-src": ["'self'", "unpkg.com"],
      "style-src": ["'self'", "unpkg.com"],
      "font-src": ["'self'", "fonts.gstatic.com"],
      "form-action": ["'self'"]
    },
  })
);

// view engine setup
app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'ejs');

app.use(session({ secret: 'work hard', saveUninitialized: true, resave: true, cookie : { sameSite: 'strict', secure: true } }));
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

app.use('/flightbooking', flightBookingRouter);
app.use('/airports', airportsRouter);
app.use('/', indexRouter);

// catch 404 and forward to error handler
app.use((req, res, next) => {
  next(createError(404));
});

// error handler
app.use((err, req, res, next) => {
  // set locals, only providing error in development
  console.log(err);
  res.locals.message = err.message;
  res.locals.error = req.app.get('env') === 'development' ? err : {};

  res.status(err.status || 500).send({
    message: err.message
  });
});

module.exports = app;
