<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import { resolveOperationsBranding } from 'shared/composables/useOperationsBranding';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';

export default {
  components: {
    GoogleOAuthButton,
    Spinner,
    SimpleDivider,
    MfaVerification,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
    operationsBranding() {
      return resolveOperationsBranding(this.globalConfig);
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      // Use a method to get the translated text to avoid dynamic key warning
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      // wait for idle state
      this.requestIdleCallbackPolyfill(() => {
        // Remove the error query param from the url
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      // MFA verification successful, continue with login
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <main class="flex flex-col w-full min-h-screen py-20 bg-[#0B0E14] bg-[radial-gradient(circle_at_center,rgba(0,82,255,0.1)_0%,transparent_50%)] sm:px-6 lg:px-8">
    <section class="max-w-5xl mx-auto">
      <img
        :src="operationsBranding.logo"
        :alt="operationsBranding.providerName"
        class="block w-auto h-16 mx-auto"
      />
      <h2 class="mt-6 text-3xl font-medium text-center text-white">
        {{ replaceInstallationName($t('LOGIN.TITLE')) }}
      </h2>
      <p v-if="showSignupLink" class="mt-3 text-sm text-center text-slate-400">
        {{ $t('COMMON.OR') }}
        <router-link to="auth/signup" class="lowercase text-[#0052FF] hover:text-[#003dbf]">
          {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
        </router-link>
      </p>
    </section>

    <!-- MFA Verification Section -->
    <section v-if="mfaRequired" class="mt-11">
      <MfaVerification
        :mfa-token="mfaToken"
        @verified="handleMfaVerified"
        @cancel="handleMfaCancel"
      />
    </section>

    <!-- Regular Login Section -->
    <section
      v-else
      class="sm:mx-auto mt-11 sm:w-full sm:max-w-lg bg-[#0B0E14]/50 border border-[#24292F] backdrop-blur-sm p-11 sm:shadow-2xl sm:rounded-2xl"
      :class="{
        'mb-8 mt-15': !showGoogleOAuth,
        'animate-wiggle': loginApi.hasErrored,
      }"
    >
      <div v-if="!email">
        <div class="flex flex-col gap-4">
          <GoogleOAuthButton v-if="showGoogleOAuth" />
          <div v-if="showSamlLogin" class="text-center">
            <router-link
              to="/app/login/sso"
              class="inline-flex justify-center w-full px-4 py-3 items-center bg-black/20 rounded-xl shadow-sm ring-1 ring-inset ring-[#24292F] focus:outline-offset-0 hover:bg-black/40 text-white transition-colors"
            >
              <Icon
                icon="i-lucide-lock-keyhole"
                class="size-5 text-slate-400"
              />
              <span class="ml-2 text-base font-medium text-white">
                {{ $t('LOGIN.SAML.LABEL') }}
              </span>
            </router-link>
          </div>
          <SimpleDivider
            v-if="showGoogleOAuth || showSamlLogin"
            :label="$t('COMMON.OR')"
            class="uppercase"
          />
        </div>
        <form class="space-y-5" @submit.prevent="submitFormLogin">
          <!-- Email Input -->
          <div>
            <label for="email_address" class="flex justify-between text-sm font-medium leading-6 text-white mb-1">
              {{ $t('LOGIN.EMAIL.LABEL') }}
            </label>
            <input
              id="email_address"
              v-model="credentials.email"
              name="email_address"
              type="text"
              data-testid="email_input"
              :tabindex="1"
              required
              :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
              @input="v$.credentials.email.$touch"
              class="block w-full rounded-xl border-0 px-3 py-3 appearance-none shadow-sm ring-1 ring-inset text-white placeholder:text-slate-500 focus:ring-2 focus:ring-inset focus:ring-[#0052FF] sm:text-sm sm:leading-6 outline-none bg-black/20"
              :class="v$.credentials.email.$error ? 'ring-red-500' : 'ring-[#24292F]'"
              style="color: #1a1a1a !important; background-color: #ffffff !important;"
            />
            <p v-if="v$.credentials.email.$error" class="mt-2 text-sm text-red-500">
              {{ $t('LOGIN.EMAIL.ERROR') }}
            </p>
          </div>
          
          <!-- Password Input -->
          <div>
            <div class="flex justify-between items-center mb-1">
              <label for="password" class="text-sm font-medium leading-6 text-white">
                {{ $t('LOGIN.PASSWORD.LABEL') }}
              </label>
              <p v-if="!globalConfig.disableUserProfileUpdate">
                <router-link
                  to="auth/reset/password"
                  class="text-sm text-[#0052FF] hover:text-[#003dbf]"
                  tabindex="4"
                >
                  {{ $t('LOGIN.FORGOT_PASSWORD') }}
                </router-link>
              </p>
            </div>
            <input
              id="password"
              v-model="credentials.password"
              type="password"
              name="password"
              data-testid="password_input"
              required
              :tabindex="2"
              :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
              @input="v$.credentials.password.$touch"
              class="block w-full rounded-xl border-0 px-3 py-3 appearance-none shadow-sm ring-1 ring-inset text-white placeholder:text-slate-500 focus:ring-2 focus:ring-inset focus:ring-[#0052FF] sm:text-sm sm:leading-6 outline-none bg-black/20"
              :class="v$.credentials.password.$error ? 'ring-red-500' : 'ring-[#24292F]'"
              style="color: #1a1a1a !important; background-color: #ffffff !important;"
            />
          </div>

          <button
            type="submit"
            data-testid="submit_button"
            class="flex items-center w-full justify-center rounded-xl bg-[#0052FF] py-3 px-3 text-base font-medium text-white shadow-sm hover:bg-[#003dbf] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#0052FF] cursor-pointer transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed"
            :tabindex="3"
            :disabled="loginApi.showLoading"
          >
            <Spinner v-if="loginApi.showLoading" size="" class="mr-2" />
            <span>Acessar Central de Comando</span>
          </button>
        </form>
      </div>
      <div v-else class="flex items-center justify-center">
        <Spinner color-scheme="primary" size="" />
      </div>
    </section>
  </main>
</template>
